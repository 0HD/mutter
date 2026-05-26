// bridge.cpp — C-ABI implementation wrapping libmumble.
//
// This is the Phase 3a connect path: TCP + TLS handshake, Version +
// Authenticate, and event dispatch for incoming ChannelState / UserState /
// TextMessage / ServerSync / Reject / UserRemove / ChannelRemove /
// PermissionDenied. Audio and recording arrive in later phases.

#include "mumble_bridge.h"
#include "audio_engine.h"

#include "mumble/Cert.hpp"
#include "mumble/Connection.hpp"
#include "mumble/Key.hpp"
#include "mumble/Lib.hpp"
#include "mumble/Message.hpp"
#include "mumble/Pack.hpp"
#include "mumble/Peer.hpp"
#include "mumble/Types.hpp"

#include "dart_api_dl.h"

#include <openssl/bio.h>
#include <openssl/buffer.h>
#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/x509.h>

#include <winsock2.h>
#include <ws2tcpip.h>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

namespace {

constexpr const char* kClientRelease = "mutter";

// JSON-escape a string and append to out.
void appendJsonEscaped(std::string& out, const std::string& s) {
    for (char c : s) {
        switch (c) {
            case '"':  out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\b': out += "\\b"; break;
            case '\f': out += "\\f"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (static_cast<unsigned char>(c) < 0x20) {
                    char buf[8];
                    std::snprintf(buf, sizeof(buf), "\\u%04x", c);
                    out += buf;
                } else {
                    out += c;
                }
        }
    }
}

void appendJsonString(std::string& out, const char* key, const std::string& v) {
    out += '"';
    out += key;
    out += "\":\"";
    appendJsonEscaped(out, v);
    out += "\"";
}

void appendJsonU32(std::string& out, const char* key, uint32_t v) {
    out += '"';
    out += key;
    out += "\":";
    out += std::to_string(v);
}

void appendJsonI32(std::string& out, const char* key, int32_t v) {
    out += '"';
    out += key;
    out += "\":";
    out += std::to_string(v);
}

void appendJsonBool(std::string& out, const char* key, bool v) {
    out += '"';
    out += key;
    out += "\":";
    out += v ? "true" : "false";
}

struct BridgeState {
    std::atomic<bool> initialized{false};
    std::atomic<int64_t> event_port{0};

    std::mutex mu;
    std::shared_ptr<mumble::Connection> connection;
    std::unique_ptr<mumble::Peer> peer;
    std::thread setup_thread;
    std::thread halt_thread;
    std::thread ping_thread;
    std::atomic<bool> halting{false};
    std::atomic<bool> ping_stop{false};

    std::string username;
    std::string password;
    std::vector<std::string> tokens;
    uint32_t local_session = UINT32_MAX;

    std::unique_ptr<AudioEngine> audio;
    std::atomic<bool> self_mute{false};
    std::atomic<bool> self_deaf{false};
    std::atomic<bool> duck_others{true};
    std::atomic<float> input_gain_db{0.0f};
    std::atomic<float> output_gain_db{0.0f};
    std::atomic<uint32_t> opus_bitrate{32000};
};

BridgeState& S() {
    static BridgeState s;
    return s;
}

// Forward declarations so dispatch_pack/on_connection_* can reach into the
// audio engine helpers below.
void start_audio_engine();
void stop_audio_engine();
void start_ping_thread();
void stop_ping_thread();
void send_message(const mumble::tcp::Message& msg);
void send_audio_via_tunnel(std::vector<std::byte> opusData,
                           uint64_t frameNumber, bool terminator);

void post_json(const std::string& s) {
    int64_t port = S().event_port.load();
    if (port == 0) return;
    Dart_CObject obj;
    obj.type = Dart_CObject_kString;
    obj.value.as_string = const_cast<char*>(s.c_str());
    Dart_PostCObject_DL(port, &obj);
}

} // anonymous namespace

extern "C" void audio_log(const char* line) {
    if (!line) return;
    std::string j = "{\"type\":\"diag\",\"source\":\"audio\",";
    appendJsonString(j, "message", line);
    j += "}";
    post_json(j);
}

extern "C" void audio_publish_input_level(float rms) {
    char buf[64];
    std::snprintf(buf, sizeof(buf), "%.4f", rms);
    std::string j = "{\"type\":\"audio_level\",\"rms\":";
    j += buf;
    j += "}";
    post_json(j);
}

namespace {

void post_state(const char* state, const std::string& reason = "") {
    std::string j = "{\"type\":\"connection_state\",\"state\":\"";
    j += state;
    j += "\"";
    if (!reason.empty()) {
        j += ",";
        appendJsonString(j, "reason", reason);
    }
    j += "}";
    post_json(j);
}

bool resolve_host(const std::string& host, std::string& out_ip) {
    addrinfo hints{};
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    addrinfo* res = nullptr;
    int rc = getaddrinfo(host.c_str(), nullptr, &hints, &res);
    if (rc != 0 || !res) return false;

    char buf[INET6_ADDRSTRLEN] = {};
    if (res->ai_family == AF_INET) {
        auto* sa = reinterpret_cast<sockaddr_in*>(res->ai_addr);
        inet_ntop(AF_INET, &sa->sin_addr, buf, sizeof(buf));
    } else if (res->ai_family == AF_INET6) {
        auto* sa = reinterpret_cast<sockaddr_in6*>(res->ai_addr);
        inet_ntop(AF_INET6, &sa->sin6_addr, buf, sizeof(buf));
    }
    freeaddrinfo(res);
    out_ip = buf;
    return !out_ip.empty();
}

// Generate a fresh self-signed cert and key so the server accepts our TLS
// handshake. libmumble doesn't expose a one-shot generator, so we use OpenSSL
// directly here. We re-export the PEM if the caller wants to persist it.
struct CertPair {
    mumble::Cert cert;
    mumble::Key  key;
    bool ok = false;
};

CertPair generate_cert(const std::string& common_name) {
    CertPair out;
    EVP_PKEY* pkey = EVP_RSA_gen(2048);
    if (!pkey) return out;

    X509* x = X509_new();
    if (!x) { EVP_PKEY_free(pkey); return out; }

    ASN1_INTEGER_set(X509_get_serialNumber(x), 1);
    X509_gmtime_adj(X509_getm_notBefore(x), 0);
    X509_gmtime_adj(X509_getm_notAfter(x), 60L * 60 * 24 * 365 * 10);
    X509_set_pubkey(x, pkey);

    X509_NAME* name = X509_get_subject_name(x);
    X509_NAME_add_entry_by_txt(name, "CN", MBSTRING_ASC,
        reinterpret_cast<const unsigned char*>(common_name.c_str()), -1, -1, 0);
    X509_set_issuer_name(x, name);
    X509_sign(x, pkey, EVP_sha256());

    // Convert X509 -> PEM, then PEM -> mumble::Cert
    BIO* bio = BIO_new(BIO_s_mem());
    PEM_write_bio_X509(bio, x);
    BUF_MEM* mem = nullptr;
    BIO_get_mem_ptr(bio, &mem);
    std::string cert_pem(mem->data, mem->length);
    BIO_free_all(bio);

    bio = BIO_new(BIO_s_mem());
    PEM_write_bio_PrivateKey(bio, pkey, nullptr, nullptr, 0, nullptr, nullptr);
    BIO_get_mem_ptr(bio, &mem);
    std::string key_pem(mem->data, mem->length);
    BIO_free_all(bio);

    X509_free(x);
    EVP_PKEY_free(pkey);

    out.cert = mumble::Cert(std::string_view{cert_pem});
    out.key  = mumble::Key(std::string_view{key_pem}, true);
    out.ok   = static_cast<bool>(out.cert) && static_cast<bool>(out.key);
    return out;
}

// Dispatch one incoming TCP pack: deserialize into the typed message and
// post a JSON event for ones the UI cares about. Best-effort — unknown or
// unhandled types are silently dropped so we don't spam the UI.
void dispatch_pack(mumble::tcp::Pack& pack) {
    using Type = mumble::tcp::Message::Type;
    const auto type = mumble::tcp::Message::type(pack);

    switch (type) {
        case Type::ServerSync: {
            mumble::tcp::Message::ServerSync m;
            if (!pack(m)) return;
            S().local_session = m.session;
            std::string j = "{\"type\":\"server_sync\",";
            appendJsonU32(j, "session", m.session); j += ",";
            appendJsonU32(j, "maxBandwidth", m.maxBandwidth); j += ",";
            appendJsonString(j, "welcome", m.welcomeText);
            j += "}";
            post_json(j);
            start_ping_thread();
            start_audio_engine();
            break;
        }
        case Type::ChannelState: {
            mumble::tcp::Message::ChannelState m;
            if (!pack(m)) return;
            std::string j = "{\"type\":\"channel_state\",";
            appendJsonU32(j, "id", m.channelID); j += ",";
            if (m.parent.has_value()) {
                appendJsonU32(j, "parent", *m.parent); j += ",";
            }
            appendJsonString(j, "name", m.name); j += ",";
            appendJsonI32(j, "position", m.position); j += ",";
            appendJsonBool(j, "temporary", m.temporary); j += ",";
            appendJsonU32(j, "maxUsers", m.maxUsers); j += ",";
            appendJsonString(j, "description", m.description);
            j += "}";
            post_json(j);
            break;
        }
        case Type::ChannelRemove: {
            mumble::tcp::Message::ChannelRemove m;
            if (!pack(m)) return;
            std::string j = "{\"type\":\"channel_remove\",";
            appendJsonU32(j, "id", m.channelID);
            j += "}";
            post_json(j);
            break;
        }
        case Type::UserState: {
            mumble::tcp::Message::UserState m;
            if (!pack(m)) return;
            std::string j = "{\"type\":\"user_state\",";
            appendJsonU32(j, "session", m.session); j += ",";
            appendJsonU32(j, "channelId", m.channelID); j += ",";
            appendJsonString(j, "name", m.name); j += ",";
            appendJsonBool(j, "mute", m.mute); j += ",";
            appendJsonBool(j, "deaf", m.deaf); j += ",";
            appendJsonBool(j, "selfMute", m.selfMute); j += ",";
            appendJsonBool(j, "selfDeaf", m.selfDeaf); j += ",";
            appendJsonBool(j, "suppress", m.suppress); j += ",";
            appendJsonBool(j, "prioritySpeaker", m.prioritySpeaker); j += ",";
            appendJsonBool(j, "recording", m.recording); j += ",";
            appendJsonString(j, "comment", m.comment);
            j += "}";
            post_json(j);
            break;
        }
        case Type::UserRemove: {
            mumble::tcp::Message::UserRemove m;
            if (!pack(m)) return;
            std::string j = "{\"type\":\"user_remove\",";
            appendJsonU32(j, "session", m.session); j += ",";
            appendJsonString(j, "reason", m.reason); j += ",";
            appendJsonBool(j, "ban", m.ban);
            j += "}";
            post_json(j);
            break;
        }
        case Type::TextMessage: {
            mumble::tcp::Message::TextMessage m;
            if (!pack(m)) return;
            std::string j = "{\"type\":\"text_message\",";
            appendJsonU32(j, "actor", m.actor); j += ",";
            j += "\"channels\":[";
            for (size_t i = 0; i < m.channelID.size(); ++i) {
                if (i) j += ",";
                j += std::to_string(m.channelID[i]);
            }
            j += "],\"sessions\":[";
            for (size_t i = 0; i < m.session.size(); ++i) {
                if (i) j += ",";
                j += std::to_string(m.session[i]);
            }
            j += "],";
            appendJsonString(j, "text", m.message);
            j += "}";
            post_json(j);
            break;
        }
        case Type::Reject: {
            mumble::tcp::Message::Reject m;
            if (!pack(m)) return;
            const char* kind = "Reject";
            switch (m.rejectType) {
                case mumble::tcp::Message::Reject::WrongVersion: kind = "WrongVersion"; break;
                case mumble::tcp::Message::Reject::InvalidUsername: kind = "InvalidUsername"; break;
                case mumble::tcp::Message::Reject::WrongUserPW: kind = "WrongUserPW"; break;
                case mumble::tcp::Message::Reject::WrongServerPW: kind = "WrongServerPW"; break;
                case mumble::tcp::Message::Reject::UsernameInUse: kind = "UsernameInUse"; break;
                case mumble::tcp::Message::Reject::ServerFull: kind = "ServerFull"; break;
                case mumble::tcp::Message::Reject::NoCertificate: kind = "NoCertificate"; break;
                case mumble::tcp::Message::Reject::AuthenticatorFail: kind = "AuthenticatorFail"; break;
                default: break;
            }
            std::string reason = m.reason.empty() ? std::string{kind} : m.reason;
            post_state("error", reason);
            break;
        }
        case Type::PermissionDenied: {
            mumble::tcp::Message::PermissionDenied m;
            if (!pack(m)) return;
            std::string j = "{\"type\":\"permission_denied\",";
            appendJsonString(j, "reason", m.reason);
            j += "}";
            post_json(j);
            break;
        }
        case Type::ServerConfig: {
            mumble::tcp::Message::ServerConfig m;
            if (!pack(m)) return;
            std::string j = "{\"type\":\"server_config\",";
            appendJsonString(j, "welcome", m.welcomeText); j += ",";
            appendJsonU32(j, "maxUsers", m.maxUsers); j += ",";
            appendJsonU32(j, "maxBandwidth", m.maxBandwidth);
            j += "}";
            post_json(j);
            break;
        }
        case Type::UDPTunnel: {
            // Audio piggybacked over the TCP control channel (the server
            // doesn't have a UDP path to us, or we never negotiated one).
            mumble::tcp::Message::UDPTunnel m;
            if (!pack(m)) return;
            const auto innerType = mumble::udp::Message::type(m.pack);
            if (innerType != mumble::udp::Message::Type::Audio) return;
            mumble::udp::Message::Audio audio;
            if (!m.pack(audio)) return;
            auto& s = S();
            if (s.audio && audio.senderSession.has_value()) {
                s.audio->onIncomingAudio(*audio.senderSession, audio.frameNumber,
                                         audio.opusData, audio.isTerminator);
                // Speaking indicator: emit a user_talking event only on
                // transitions so we don't flood the Dart isolate with one
                // event per 10ms packet.
                static std::unordered_map<uint32_t, bool> talking;
                static std::mutex talking_mu;
                const uint32_t sess = *audio.senderSession;
                const bool nowTalking = !audio.isTerminator;
                bool emit = false;
                {
                    std::lock_guard<std::mutex> lk(talking_mu);
                    auto it = talking.find(sess);
                    if (it == talking.end() || it->second != nowTalking) {
                        talking[sess] = nowTalking;
                        emit = true;
                    }
                }
                if (emit) {
                    std::string j = "{\"type\":\"user_talking\",";
                    appendJsonU32(j, "session", sess); j += ",";
                    appendJsonBool(j, "talking", nowTalking);
                    j += "}";
                    post_json(j);
                }
            }
            break;
        }
        case Type::Ping:
        case Type::CryptSetup:
        case Type::CodecVersion:
            // Not surfaced; handled later or ignored for the no-audio path.
            break;
        default:
            break;
    }
}

void send_message(const mumble::tcp::Message& msg) {
    auto& s = S();
    std::lock_guard<std::mutex> lk(s.mu);
    if (!s.connection) return;
    s.connection->write(mumble::tcp::Pack(msg).buf());
}

void send_audio_via_tunnel(std::vector<std::byte> opusData,
                           uint64_t frameNumber, bool terminator) {
    mumble::udp::Message::Audio audio;
    audio.direction = mumble::udp::Message::Audio::ClientToServer;
    audio.target = 0; // normal talk
    audio.frameNumber = frameNumber;
    audio.opusData = std::move(opusData);
    audio.isTerminator = terminator;

    mumble::tcp::Message::UDPTunnel tunnel;
    tunnel.pack = mumble::udp::Pack(audio);
    send_message(tunnel);
}

void start_ping_thread() {
    auto& s = S();
    if (s.ping_thread.joinable()) return;
    s.ping_stop.store(false);
    s.ping_thread = std::thread([]() {
        auto& s = S();
        while (!s.ping_stop.load()) {
            for (int i = 0; i < 10 && !s.ping_stop.load(); ++i) {
                std::this_thread::sleep_for(std::chrono::seconds(1));
            }
            if (s.ping_stop.load()) break;
            // Send a Mumble protocol Ping. The struct defaults are fine —
            // the server doesn't strictly require any field to be non-zero.
            mumble::tcp::Message::Ping ping;
            send_message(ping);
        }
    });
}

void stop_ping_thread() {
    auto& s = S();
    s.ping_stop.store(true);
    if (s.ping_thread.joinable()) s.ping_thread.join();
}

void start_audio_engine() {
    auto& s = S();
    if (s.audio) return;
    s.audio = std::make_unique<AudioEngine>();
    s.audio->setDuckOthers(s.duck_others.load());
    s.audio->setMuted(s.self_mute.load());
    s.audio->setDeafened(s.self_deaf.load());
    s.audio->setInputGainDb(s.input_gain_db.load());
    s.audio->setOutputGainDb(s.output_gain_db.load());
    s.audio->setOpusBitrate(s.opus_bitrate.load());
    if (!s.audio->start(send_audio_via_tunnel)) {
        s.audio.reset();
        // Surface the failure but don't sever the connection — text-only is
        // still useful.
        std::string j = "{\"type\":\"permission_denied\",";
        appendJsonString(j, "reason", "Could not start audio engine "
                                       "(no microphone/speaker, or device busy).");
        j += "}";
        post_json(j);
    }
}

void stop_audio_engine() {
    auto& s = S();
    if (!s.audio) return;
    s.audio->stop();
    s.audio.reset();
}

void on_connection_opened() {
    // Send Version, then Authenticate.
    mumble::tcp::Message::Version ver;
    ver.version = mumble::lib::version();
    ver.release = kClientRelease;
    ver.os = "Windows";
    send_message(ver);

    mumble::tcp::Message::Authenticate auth;
    auth.username = S().username;
    auth.password = S().password;
    auth.tokens = S().tokens;
    auth.opus = true;
    send_message(auth);

    post_state("authenticating");
}

void on_connection_closed() {
    stop_ping_thread();
    stop_audio_engine();
    post_state("disconnected");
}

void on_connection_failed(mumble::Code code) {
    stop_ping_thread();
    stop_audio_engine();
    std::string reason = std::string{mumble::text(code)};
    post_state("error", reason);
}

void teardown_locked() {
    auto& s = S();
    s.halting.store(true);
    s.ping_stop.store(true);
    if (s.audio) {
        s.audio->stop();
        s.audio.reset();
    }
    if (s.peer) {
        s.peer->stopTCP();
    }
    if (s.connection) {
        s.connection.reset();
    }
    s.peer.reset();
    s.local_session = UINT32_MAX;
    s.halting.store(false);
}

void start_connection(std::string host, uint16_t port) {
    auto& s = S();

    post_state("connecting");

    std::string ip;
    if (!resolve_host(host, ip)) {
        post_state("error", "Could not resolve " + host);
        return;
    }

    auto certPair = generate_cert(s.username.empty() ? "mutter" : s.username);
    if (!certPair.ok) {
        post_state("error", "Failed to generate client certificate");
        return;
    }

    mumble::Endpoint peerEndpoint{ mumble::IP{ std::string_view{ip} }, port };
    auto [code, sock] = mumble::Peer::connect(peerEndpoint);
    if (code != mumble::Code::Success) {
        post_state("error", "TCP connect failed: " + std::string{mumble::text(code)});
        return;
    }

    auto conn = std::make_shared<mumble::Connection>(sock, false);
    conn->setCert({ certPair.cert }, certPair.key);

    // Register the connection in the bridge state BEFORE wiring feedback so
    // that the `opened` callback (which can fire from libmumble's I/O thread
    // any time after this point) can find it via send_message().
    {
        std::lock_guard<std::mutex> lk(s.mu);
        s.connection = conn;
    }

    mumble::Connection::Feedback fb;
    fb.opened  = []() { on_connection_opened(); };
    fb.closed  = []() { on_connection_closed(); };
    fb.failed  = [](mumble::Code c) { on_connection_failed(c); };
    fb.timeout = []() -> uint32_t { return 10000; };
    fb.timeouts = []() -> uint32_t { return 6; };
    fb.pack    = [](mumble::tcp::Pack& pack) { dispatch_pack(pack); };

    auto setupCode = (*conn)(fb);
    if (setupCode != mumble::Code::Success) {
        {
            std::lock_guard<std::mutex> lk(s.mu);
            s.connection.reset();
        }
        post_state("error", "TLS setup failed: " + std::string{mumble::text(setupCode)});
        return;
    }

    auto peer = std::make_unique<mumble::Peer>();
    peer->addTCP(conn);

    mumble::Peer::FeedbackTCP pfb;
    pfb.failed = [](mumble::Code c) {
        post_state("error", "TCP peer failed: " + std::string{mumble::text(c)});
    };
    pfb.timeout = []() -> uint32_t { return 10000; };

    auto startCode = peer->startTCP(pfb);
    if (startCode != mumble::Code::Success) {
        post_state("error", "Peer start failed: " + std::string{mumble::text(startCode)});
        return;
    }

    {
        std::lock_guard<std::mutex> lk(s.mu);
        s.peer = std::move(peer);
    }
}

} // namespace

extern "C" {

int mb_init(void) {
    auto& s = S();
    if (s.initialized.exchange(true)) return MB_ERR_ALREADY_INIT;

    WSADATA wsa{};
    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) {
        s.initialized.store(false);
        return MB_ERR_INTERNAL;
    }
    if (mumble::lib::init() != mumble::Code::Success) {
        WSACleanup();
        s.initialized.store(false);
        return MB_ERR_INTERNAL;
    }
    return MB_OK;
}

void mb_shutdown(void) {
    auto& s = S();
    if (!s.initialized.exchange(false)) return;
    mb_disconnect();
    mumble::lib::deinit();
    WSACleanup();
}

const char* mb_version(void) {
    return "mutter-bridge 0.0.1";
}

void mb_set_event_port(int64_t send_port_id) {
    S().event_port.store(send_port_id);
}

int mb_init_dart_api(void* dart_api_dl_data) {
    return Dart_InitializeApiDL(dart_api_dl_data) == 0 ? MB_OK : MB_ERR_INTERNAL;
}

int mb_connect(const mb_connect_params* params) {
    auto& s = S();
    if (!s.initialized.load()) return MB_ERR_NOT_INITIALIZED;
    if (!params || !params->host || !params->username) return MB_ERR_INVALID_ARG;

    {
        std::lock_guard<std::mutex> lk(s.mu);
        if (s.connection || s.peer) {
            // Already connected/connecting — disconnect first.
            teardown_locked();
        }
        s.username = params->username;
        s.password = params->password ? params->password : "";
        s.tokens.clear();
        if (params->tokens) {
            for (const char* const* p = params->tokens; *p; ++p) {
                s.tokens.emplace_back(*p);
            }
        }
    }

    std::string host = params->host;
    uint16_t port = params->port ? params->port : 64738;

    if (s.setup_thread.joinable()) s.setup_thread.join();
    s.setup_thread = std::thread([host, port]() { start_connection(host, port); });

    return MB_OK;
}

void mb_disconnect(void) {
    auto& s = S();
    {
        std::lock_guard<std::mutex> lk(s.mu);
        teardown_locked();
    }
    if (s.setup_thread.joinable()) s.setup_thread.join();
    if (s.ping_thread.joinable())  s.ping_thread.join();
    // Explicitly announce — libmumble's `closed` callback may or may not fire
    // when we initiate the teardown ourselves.
    post_state("disconnected");
}

// --- Stubs to be filled in next phases. ---

void mb_join_channel(uint32_t channel_id) {
    mumble::tcp::Message::UserState m;
    m.session = S().local_session;
    m.channelID = channel_id;
    send_message(m);
}

void mb_send_text_channel(uint32_t channel_id, bool include_tree, const char* text) {
    if (!text) return;
    mumble::tcp::Message::TextMessage m;
    if (include_tree) m.treeID.push_back(channel_id);
    else m.channelID.push_back(channel_id);
    m.message = text;
    send_message(m);
}

void mb_send_text_user(uint32_t session_id, const char* text) {
    if (!text) return;
    mumble::tcp::Message::TextMessage m;
    m.session.push_back(session_id);
    m.message = text;
    send_message(m);
}

void mb_set_listen_channel(uint32_t channel_id, bool listen) {
    mumble::tcp::Message::UserState m;
    m.session = S().local_session;
    if (listen) m.listeningChannelAdd.push_back(channel_id);
    else        m.listeningChannelRemove.push_back(channel_id);
    send_message(m);
}

void mb_set_self_mute(bool mute) {
    auto& s = S();
    s.self_mute.store(mute);
    if (s.audio) s.audio->setMuted(mute);
    mumble::tcp::Message::UserState m;
    m.session = s.local_session;
    m.selfMute = mute;
    send_message(m);
}

void mb_set_self_deaf(bool deaf) {
    auto& s = S();
    s.self_deaf.store(deaf);
    if (s.audio) s.audio->setDeafened(deaf);
    // Mumble convention: deafening implies muting.
    if (deaf) {
        s.self_mute.store(true);
        if (s.audio) s.audio->setMuted(true);
    }
    mumble::tcp::Message::UserState m;
    m.session = s.local_session;
    m.selfDeaf = deaf;
    if (deaf) m.selfMute = true;
    send_message(m);
}

void mb_set_self_comment(const char* comment) {
    if (!comment) return;
    mumble::tcp::Message::UserState m;
    m.session = S().local_session;
    m.comment = comment;
    send_message(m);
}

void  mb_set_tx_mode(mb_tx_mode)                             {}
void  mb_set_ptt_pressed(bool)                               {}
void  mb_set_vad_threshold(float)                            {}
void  mb_set_voice_hold_ms(uint32_t)                         {}

char* mb_list_input_devices(void)                            { return nullptr; }
char* mb_list_output_devices(void)                           { return nullptr; }
int   mb_set_input_device(const char*)                       { return MB_OK; }
int   mb_set_output_device(const char*)                      { return MB_OK; }

void mb_set_input_gain_db(float db) {
    auto& s = S();
    s.input_gain_db.store(db);
    if (s.audio) s.audio->setInputGainDb(db);
}

void mb_set_output_gain_db(float db) {
    auto& s = S();
    s.output_gain_db.store(db);
    if (s.audio) s.audio->setOutputGainDb(db);
}

void  mb_set_user_gain_db(uint32_t, float)                   {}
void  mb_set_noise_suppression(bool)                         {}
void  mb_set_attenuate_others_db(float)                      {}

void mb_set_opus_bitrate(uint32_t bps) {
    auto& s = S();
    s.opus_bitrate.store(bps);
    if (s.audio) s.audio->setOpusBitrate(bps);
}

void  mb_set_opus_frames_per_packet(uint32_t)                {}

void mb_set_audio_ducking(bool duck) {
    auto& s = S();
    const bool was = s.duck_others.exchange(duck);
    if (was == duck) return;
    if (s.audio) {
        s.audio->stop();
        s.audio.reset();
        start_audio_engine();
    }
}

void  mb_voice_target_clear(uint8_t)                         {}
void  mb_voice_target_add_users(uint8_t, const uint32_t*, size_t) {}
void  mb_voice_target_add_channel(uint8_t, uint32_t, bool, bool)  {}
void  mb_use_voice_target(uint8_t)                           {}

int   mb_recording_start(const char*, mb_record_format, mb_record_mode) { return MB_OK; }
void  mb_recording_stop(void)                                {}
bool  mb_recording_active(void)                              { return false; }

int   mb_generate_self_signed_cert(const char*, const char*, char**, char**) { return MB_OK; }

void  mb_free_string(char* s) { if (s) std::free(s); }

} // extern "C"
