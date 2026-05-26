// audio_engine.h
//
// First-cut audio pipeline for mutter. WASAPI shared-mode capture +
// playback, Opus encode/decode via libmumble, simple per-session jitter
// buffers and mixer. Transport is via UDPTunnel (UDP audio payload wrapped
// in a TCP control frame) — works without negotiating UDP crypto and is what
// the official Mumble client falls back to when UDP is blocked.

#ifndef NEWMUMBLE_AUDIO_ENGINE_H
#define NEWMUMBLE_AUDIO_ENGINE_H

#include "mumble/Opus.hpp"

#include <atomic>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <thread>
#include <unordered_map>
#include <vector>

// Implemented by bridge.cpp; posts a "diag" event to the Dart event port. The
// audio engine uses this to surface WASAPI setup failures.
extern "C" void audio_log(const char* line);

// Implemented by bridge.cpp; posts an "audio_level" event with the most
// recent mic input RMS (in [0,1]). Called periodically from the capture loop.
extern "C" void audio_publish_input_level(float rms);

class AudioEngine {
public:
    // Outgoing-packet callback. `opusData` is a single Opus-encoded frame for
    // 10ms of mono 48kHz audio. `frameNumber` is monotonic per stream.
    using OutgoingCallback = std::function<void(
        std::vector<std::byte> opusData, uint64_t frameNumber, bool terminator)>;

    AudioEngine();
    ~AudioEngine();

    bool start(OutgoingCallback outgoing);
    void stop();

    // Whether to use the COMMUNICATIONS endpoint role for the WASAPI streams
    // (which causes Windows to duck other apps' audio while we're open). Must
    // be set BEFORE start() — runtime changes require a stop()/start() cycle.
    void setDuckOthers(bool duck) { _duckOthers = duck; }
    bool duckOthers() const { return _duckOthers; }

    void setMuted(bool muted)     { _muted.store(muted); }
    void setDeafened(bool deaf)   { _deafened.store(deaf); }
    void setInputGainDb(float db) { _inputGain.store(linearFromDb(db)); }
    void setOutputGainDb(float db){ _outputGain.store(linearFromDb(db)); }

    // Whether the capture loop should actually transmit audio. The TX mode
    // (continuous / PTT / VAD) lives in the bridge; the bridge flips this
    // accordingly. Defaults to true (matches the existing continuous mode).
    void setTransmitting(bool t)  { _transmitting.store(t); }

    // Per-session output gain (linear multiplier, kept in a map). Used by the
    // mixer to attenuate or amplify individual users.
    void setUserGainDb(uint32_t session, float db);
    void setOpusBitrate(uint32_t bps) {
        _opusBitrate = bps;
        if (_encoder) _encoder->setBitrate(bps);
    }

    bool muted()    const { return _muted.load(); }
    bool deafened() const { return _deafened.load(); }

    // Called by the bridge whenever a UDP audio frame arrives for `session`.
    void onIncomingAudio(uint32_t session, uint64_t frameNumber,
                         const std::vector<std::byte>& opusData,
                         bool terminator);

    void resetSession(uint32_t session);

private:
    static float linearFromDb(float db) {
        // 10^(db/20), but cheap and safe for sane ranges.
        return std::pow(10.0f, db / 20.0f);
    }

    void captureLoop();
    void renderLoop();

    // 48 kHz mono frames, 10 ms each → 480 samples.
    static constexpr uint32_t kSampleRate    = 48000;
    static constexpr uint32_t kFrameSamples  = 480;
    static constexpr uint32_t kFrameMs       = 10;

    OutgoingCallback _outgoing;

    std::atomic<bool> _running{false};
    std::atomic<bool> _muted{false};
    std::atomic<bool> _deafened{false};
    std::atomic<bool> _transmitting{true};
    std::atomic<float> _inputGain{1.0f};
    std::atomic<float> _outputGain{1.0f};
    bool _duckOthers{true};
    uint32_t _opusBitrate{32000};

    std::mutex _userGainsMu;
    std::unordered_map<uint32_t, float> _userGains;

    std::thread _captureThread;
    std::thread _renderThread;

    // Encoder/decoder ownership.
    std::unique_ptr<mumble::Opus::Encoder> _encoder;
    std::mutex _decodersMu;
    std::unordered_map<uint32_t, std::unique_ptr<mumble::Opus::Decoder>> _decoders;

    struct PerSession {
        std::deque<std::vector<float>> queue;  // PCM 10ms frames
        std::mutex mu;
    };
    std::mutex _sessionsMu;
    std::unordered_map<uint32_t, std::unique_ptr<PerSession>> _sessions;

    std::atomic<uint64_t> _txFrameCounter{0};
};

#endif // NEWMUMBLE_AUDIO_ENGINE_H
