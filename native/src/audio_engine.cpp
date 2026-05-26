// audio_engine.cpp — WASAPI capture/render + Opus codec + per-session mixer.

#include "audio_engine.h"

#include "mumble/Opus.hpp"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>

#include <audioclient.h>
#include <mmdeviceapi.h>
#include <objbase.h>
#include <comdef.h>

#include <gsl/span>

namespace {

constexpr REFERENCE_TIME kRefTimesPerSec  = 10000000;
constexpr REFERENCE_TIME kRefTimesPerMs   = 10000;

// Hold the requested format. We force 48 kHz mono float to keep the pipeline
// simple — WASAPI's shared-mode mixer will resample under the hood if the
// device's mix format differs.
WAVEFORMATEXTENSIBLE make_format(uint32_t channels, uint32_t sample_rate) {
    WAVEFORMATEXTENSIBLE w{};
    w.Format.wFormatTag      = WAVE_FORMAT_EXTENSIBLE;
    w.Format.nChannels       = static_cast<WORD>(channels);
    w.Format.nSamplesPerSec  = sample_rate;
    w.Format.wBitsPerSample  = 32;
    w.Format.nBlockAlign     = static_cast<WORD>(channels * sizeof(float));
    w.Format.nAvgBytesPerSec = sample_rate * w.Format.nBlockAlign;
    w.Format.cbSize          = sizeof(WAVEFORMATEXTENSIBLE) - sizeof(WAVEFORMATEX);
    w.Samples.wValidBitsPerSample = 32;
    w.dwChannelMask          = channels == 1 ? SPEAKER_FRONT_CENTER
                               : (SPEAKER_FRONT_LEFT | SPEAKER_FRONT_RIGHT);
    w.SubFormat              = KSDATAFORMAT_SUBTYPE_IEEE_FLOAT;
    return w;
}

// Resample-and-convert helper: takes interleaved float at `srcRate` Hz with
// `srcCh` channels and writes mono 48 kHz floats to `dst`. Very dumb linear
// interpolation; good enough until we add libspeexdsp.
void downmix_and_resample(const float* src, size_t srcFrames, uint32_t srcCh,
                          uint32_t srcRate, std::vector<float>& dst,
                          uint32_t dstRate) {
    // Step 1: downmix to mono in a temp buffer (in srcRate).
    std::vector<float> mono;
    mono.reserve(srcFrames);
    if (srcCh == 1) {
        mono.assign(src, src + srcFrames);
    } else {
        for (size_t i = 0; i < srcFrames; ++i) {
            float sum = 0.f;
            for (uint32_t c = 0; c < srcCh; ++c) sum += src[i * srcCh + c];
            mono.push_back(sum / static_cast<float>(srcCh));
        }
    }
    // Step 2: linear-interpolate to dstRate.
    if (srcRate == dstRate) {
        dst.insert(dst.end(), mono.begin(), mono.end());
        return;
    }
    const double ratio = static_cast<double>(srcRate) / dstRate;
    const size_t outFrames = static_cast<size_t>(mono.size() / ratio);
    dst.reserve(dst.size() + outFrames);
    for (size_t i = 0; i < outFrames; ++i) {
        const double pos = i * ratio;
        const size_t i0 = static_cast<size_t>(pos);
        const size_t i1 = std::min<size_t>(i0 + 1, mono.size() - 1);
        const float frac = static_cast<float>(pos - i0);
        dst.push_back(mono[i0] * (1.f - frac) + mono[i1] * frac);
    }
}

// Inverse: take mono 48 kHz float and produce interleaved float at
// `dstRate` × `dstCh`.
void upmix_and_resample(const float* src, size_t srcFrames,
                        uint32_t srcRate, std::vector<float>& dst,
                        uint32_t dstRate, uint32_t dstCh) {
    std::vector<float> tmp;
    if (srcRate == dstRate) {
        tmp.assign(src, src + srcFrames);
    } else {
        const double ratio = static_cast<double>(srcRate) / dstRate;
        const size_t outFrames = static_cast<size_t>(srcFrames / ratio);
        tmp.reserve(outFrames);
        for (size_t i = 0; i < outFrames; ++i) {
            const double pos = i * ratio;
            const size_t i0 = static_cast<size_t>(pos);
            const size_t i1 = std::min<size_t>(i0 + 1, srcFrames - 1);
            const float frac = static_cast<float>(pos - i0);
            tmp.push_back(src[i0] * (1.f - frac) + src[i1] * frac);
        }
    }
    dst.reserve(dst.size() + tmp.size() * dstCh);
    for (float s : tmp) {
        for (uint32_t c = 0; c < dstCh; ++c) dst.push_back(s);
    }
}

struct ComInit {
    HRESULT hr;
    ComInit()  { hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED); }
    ~ComInit() { if (SUCCEEDED(hr)) CoUninitialize(); }
};

} // namespace

AudioEngine::AudioEngine() = default;

AudioEngine::~AudioEngine() {
    stop();
}

bool AudioEngine::start(OutgoingCallback outgoing) {
    if (_running.exchange(true)) return false;
    _outgoing = std::move(outgoing);

    // The Opus encoder's bool conversion returns false until init() has
    // succeeded, so we don't check it here — init() is the source of truth.
    _encoder = std::make_unique<mumble::Opus::Encoder>(1);
    if (_encoder->init(kSampleRate, mumble::Opus::Encoder::Preset::VoIP)
        != mumble::Code::Success) {
        _encoder.reset();
        _running.store(false);
        return false;
    }
    _encoder->setBitrate(_opusBitrate);
    _encoder->toggleVBR(true);

    _captureThread = std::thread(&AudioEngine::captureLoop, this);
    _renderThread  = std::thread(&AudioEngine::renderLoop, this);
    return true;
}

void AudioEngine::stop() {
    if (!_running.exchange(false)) return;
    if (_captureThread.joinable()) _captureThread.join();
    if (_renderThread.joinable())  _renderThread.join();
    _encoder.reset();
    {
        std::lock_guard<std::mutex> lk(_decodersMu);
        _decoders.clear();
    }
    {
        std::lock_guard<std::mutex> lk(_sessionsMu);
        _sessions.clear();
    }
}

void AudioEngine::onIncomingAudio(uint32_t session, uint64_t /*frameNumber*/,
                                  const std::vector<std::byte>& opusData,
                                  bool /*terminator*/) {
    if (_deafened.load()) return;

    mumble::Opus::Decoder* dec = nullptr;
    {
        std::lock_guard<std::mutex> lk(_decodersMu);
        auto it = _decoders.find(session);
        if (it == _decoders.end()) {
            auto d = std::make_unique<mumble::Opus::Decoder>(1);
            if (d->init(kSampleRate) != mumble::Code::Success) return;
            it = _decoders.emplace(session, std::move(d)).first;
        }
        dec = it->second.get();
    }

    // Decode into a mono frame buffer. Opus decode produces packetSamples().
    std::vector<float> pcm(kFrameSamples * 6, 0.f); // worst case 60ms
    auto out = (*dec)(gsl::span<float>(pcm),
                      gsl::span<const std::byte>(opusData.data(), opusData.size()));
    if (out.empty()) return;
    pcm.resize(out.size());

    PerSession* sess = nullptr;
    {
        std::lock_guard<std::mutex> lk(_sessionsMu);
        auto it = _sessions.find(session);
        if (it == _sessions.end()) {
            it = _sessions.emplace(session, std::make_unique<PerSession>()).first;
        }
        sess = it->second.get();
    }
    {
        std::lock_guard<std::mutex> lk(sess->mu);
        // Split into 10ms chunks (480 samples) for the mixer.
        size_t i = 0;
        while (i < pcm.size()) {
            const size_t take = std::min<size_t>(kFrameSamples, pcm.size() - i);
            std::vector<float> frame(pcm.begin() + i, pcm.begin() + i + take);
            if (frame.size() < kFrameSamples) frame.resize(kFrameSamples, 0.f);
            sess->queue.push_back(std::move(frame));
            i += take;
        }
        // Drop oldest if buffer grows unbounded (>200ms worth).
        while (sess->queue.size() > 20) sess->queue.pop_front();
    }
}

void AudioEngine::resetSession(uint32_t session) {
    {
        std::lock_guard<std::mutex> lk(_decodersMu);
        _decoders.erase(session);
    }
    {
        std::lock_guard<std::mutex> lk(_sessionsMu);
        _sessions.erase(session);
    }
}

void AudioEngine::setUserGainDb(uint32_t session, float db) {
    const float linear = linearFromDb(db);
    std::lock_guard<std::mutex> lk(_userGainsMu);
    if (db == 0.0f) {
        _userGains.erase(session);
    } else {
        _userGains[session] = linear;
    }
}

void AudioEngine::captureLoop() {
    ComInit comInit;
    if (FAILED(comInit.hr)) {
        audio_log("capture: CoInitializeEx failed");
        _running.store(false);
        return;
    }

    IMMDeviceEnumerator* enumerator = nullptr;
    IMMDevice* device = nullptr;
    IAudioClient* client = nullptr;
    IAudioCaptureClient* capture = nullptr;
    HANDLE event = CreateEventW(nullptr, FALSE, FALSE, nullptr);

    auto cleanup = [&]() {
        if (capture)    capture->Release();
        if (client)     { client->Stop(); client->Release(); }
        if (device)     device->Release();
        if (enumerator) enumerator->Release();
        if (event)      CloseHandle(event);
    };

    HRESULT hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                  CLSCTX_ALL, __uuidof(IMMDeviceEnumerator),
                                  reinterpret_cast<void**>(&enumerator));
    if (FAILED(hr)) {
        char buf[128];
        std::snprintf(buf, sizeof(buf), "capture: CoCreateInstance MMDeviceEnumerator failed (0x%08lx)", hr);
        audio_log(buf);
        cleanup(); return;
    }

    // ERole controls Windows' "this is a communications app" ducking behaviour.
    // eCommunications => Windows ducks other apps while we're open.
    // eConsole        => no ducking.
    const ERole role = _duckOthers ? eCommunications : eConsole;
    hr = enumerator->GetDefaultAudioEndpoint(eCapture, role, &device);
    if ((FAILED(hr) || !device) && role == eCommunications) {
        // Some systems don't register a communications capture endpoint.
        hr = enumerator->GetDefaultAudioEndpoint(eCapture, eConsole, &device);
    }
    if (FAILED(hr) || !device) {
        char buf[128];
        std::snprintf(buf, sizeof(buf), "capture: no default capture device (0x%08lx)", hr);
        audio_log(buf);
        cleanup(); return;
    }

    hr = device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                          reinterpret_cast<void**>(&client));
    if (FAILED(hr) || !client) {
        char buf[128];
        std::snprintf(buf, sizeof(buf), "capture: device->Activate IAudioClient failed (0x%08lx)", hr);
        audio_log(buf);
        cleanup(); return;
    }

    WAVEFORMATEX* mixFormat = nullptr;
    client->GetMixFormat(&mixFormat);
    const uint32_t devRate = mixFormat ? mixFormat->nSamplesPerSec : kSampleRate;
    const uint32_t devCh   = mixFormat ? mixFormat->nChannels : 1;
    const bool     devIsFloat = mixFormat &&
        (mixFormat->wFormatTag == WAVE_FORMAT_IEEE_FLOAT ||
         (mixFormat->wFormatTag == WAVE_FORMAT_EXTENSIBLE &&
          reinterpret_cast<WAVEFORMATEXTENSIBLE*>(mixFormat)->SubFormat
              == KSDATAFORMAT_SUBTYPE_IEEE_FLOAT));

    {
        char buf[160];
        std::snprintf(buf, sizeof(buf),
                      "capture: mixFormat rate=%u ch=%u float=%d wFormatTag=0x%x",
                      devRate, devCh, devIsFloat ? 1 : 0,
                      mixFormat ? mixFormat->wFormatTag : 0);
        audio_log(buf);
    }

    if (!devIsFloat) {
        audio_log("capture: device mix format is not IEEE_FLOAT — capture disabled");
        CoTaskMemFree(mixFormat);
        cleanup();
        return;
    }

    REFERENCE_TIME bufDuration = 40 * kRefTimesPerMs;  // 40 ms buffer
    hr = client->Initialize(AUDCLNT_SHAREMODE_SHARED,
                            AUDCLNT_STREAMFLAGS_EVENTCALLBACK,
                            bufDuration, 0, mixFormat, nullptr);
    CoTaskMemFree(mixFormat);
    if (FAILED(hr)) {
        char buf[128];
        std::snprintf(buf, sizeof(buf), "capture: Initialize failed (0x%08lx)", hr);
        audio_log(buf);
        cleanup(); return;
    }

    client->SetEventHandle(event);
    hr = client->GetService(__uuidof(IAudioCaptureClient),
                            reinterpret_cast<void**>(&capture));
    if (FAILED(hr)) {
        char buf[128];
        std::snprintf(buf, sizeof(buf), "capture: GetService failed (0x%08lx)", hr);
        audio_log(buf);
        cleanup(); return;
    }

    client->Start();
    audio_log("capture: started");

    std::vector<float> mono48;
    mono48.reserve(kFrameSamples * 4);
    std::vector<std::byte> opusOut(4000);
    bool wasTransmitting = true;

    while (_running.load()) {
        const DWORD wait = WaitForSingleObject(event, 200);
        if (wait == WAIT_TIMEOUT) continue;
        if (wait != WAIT_OBJECT_0) break;

        UINT32 packetFrames = 0;
        capture->GetNextPacketSize(&packetFrames);
        while (packetFrames > 0 && _running.load()) {
            BYTE* data = nullptr;
            UINT32 frames = 0;
            DWORD flags = 0;
            hr = capture->GetBuffer(&data, &frames, &flags, nullptr, nullptr);
            if (FAILED(hr)) break;
            const bool silent = (flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0;
            if (silent) {
                mono48.insert(mono48.end(),
                              static_cast<size_t>(frames) * kSampleRate / devRate,
                              0.f);
            } else {
                downmix_and_resample(reinterpret_cast<const float*>(data),
                                     frames, devCh, devRate, mono48, kSampleRate);
            }
            capture->ReleaseBuffer(frames);
            capture->GetNextPacketSize(&packetFrames);
        }

        // Apply input gain.
        const float gain = _inputGain.load();
        const bool muted = _muted.load();
        if (gain != 1.f) {
            for (float& s : mono48) s *= gain;
        }
        // Cross-fade at TX-state transitions so an abrupt mute or PTT release
        // doesn't produce a click. Window is 5 ms (240 samples at 48 kHz).
        const bool nowTransmittingForFade = !muted && _transmitting.load();
        const size_t fadeSamples = std::min<size_t>(240, mono48.size());
        if (fadeSamples > 0) {
            if (!wasTransmitting && nowTransmittingForFade) {
                for (size_t i = 0; i < fadeSamples; ++i) {
                    mono48[i] *= float(i) / float(fadeSamples);
                }
            } else if (wasTransmitting && !nowTransmittingForFade) {
                const size_t sz = mono48.size();
                for (size_t i = 0; i < fadeSamples; ++i) {
                    mono48[sz - fadeSamples + i] *=
                        float(fadeSamples - 1 - i) / float(fadeSamples);
                }
            }
        }
        // Once we're fully silent (no transition this round), zero the buffer
        // so a hot mic isn't lying around to be encoded.
        if (muted && !(wasTransmitting && !nowTransmittingForFade)) {
            std::fill(mono48.begin(), mono48.end(), 0.f);
        }

        // Encode 10ms frames as long as we have enough samples.
        static int sinceLastLevel = 0;
        const bool nowTransmitting = !muted && _transmitting.load();
        while (mono48.size() >= kFrameSamples && _running.load()) {
            // RMS of this 10ms frame, for the UI level meter. Use raw (pre-
            // gain) signal so the meter reflects the actual mic, not where
            // the user has the slider.
            float sumSq = 0.f;
            for (uint32_t i = 0; i < kFrameSamples; ++i) {
                const float v = mono48[i];
                sumSq += v * v;
            }
            const float rms = std::sqrt(sumSq / kFrameSamples);
            if (++sinceLastLevel >= 5) {
                // ~50ms cadence (5 × 10ms frames).
                audio_publish_input_level(std::min(1.f, rms));
                sinceLastLevel = 0;
            }

            const auto bytes = (*_encoder)(
                gsl::span<std::byte>(opusOut),
                gsl::span<const float>(mono48.data(), kFrameSamples));
            mono48.erase(mono48.begin(), mono48.begin() + kFrameSamples);
            if (bytes.empty()) continue;

            std::vector<std::byte> payload(bytes.begin(), bytes.end());
            const uint64_t fn = _txFrameCounter.fetch_add(1);
            if (!_outgoing) continue;

            if (nowTransmitting) {
                _outgoing(std::move(payload), fn, false);
            } else if (wasTransmitting) {
                // Just transitioned to silent. Send one final packet flagged
                // as terminator so other clients see us stop talking.
                _outgoing(std::move(payload), fn, true);
            }
            // else: stay silent — don't send anything.
        }
        wasTransmitting = nowTransmitting;
    }

    cleanup();
}

void AudioEngine::renderLoop() {
    ComInit comInit;
    if (FAILED(comInit.hr)) {
        audio_log("render: CoInitializeEx failed");
        return;
    }

    IMMDeviceEnumerator* enumerator = nullptr;
    IMMDevice* device = nullptr;
    IAudioClient* client = nullptr;
    IAudioRenderClient* render = nullptr;
    HANDLE event = CreateEventW(nullptr, FALSE, FALSE, nullptr);

    auto cleanup = [&]() {
        if (render)     render->Release();
        if (client)     { client->Stop(); client->Release(); }
        if (device)     device->Release();
        if (enumerator) enumerator->Release();
        if (event)      CloseHandle(event);
    };

    HRESULT hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                  CLSCTX_ALL, __uuidof(IMMDeviceEnumerator),
                                  reinterpret_cast<void**>(&enumerator));
    if (FAILED(hr)) {
        char buf[128];
        std::snprintf(buf, sizeof(buf), "render: CoCreateInstance failed (0x%08lx)", hr);
        audio_log(buf);
        cleanup(); return;
    }
    const ERole role = _duckOthers ? eCommunications : eConsole;
    hr = enumerator->GetDefaultAudioEndpoint(eRender, role, &device);
    if ((FAILED(hr) || !device) && role == eCommunications) {
        hr = enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &device);
    }
    if (FAILED(hr) || !device) {
        char buf[128];
        std::snprintf(buf, sizeof(buf), "render: no default render device (0x%08lx)", hr);
        audio_log(buf);
        cleanup(); return;
    }
    hr = device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                          reinterpret_cast<void**>(&client));
    if (FAILED(hr) || !client) {
        char buf[128];
        std::snprintf(buf, sizeof(buf), "render: device->Activate failed (0x%08lx)", hr);
        audio_log(buf);
        cleanup(); return;
    }

    WAVEFORMATEX* mixFormat = nullptr;
    client->GetMixFormat(&mixFormat);
    const uint32_t devRate = mixFormat ? mixFormat->nSamplesPerSec : kSampleRate;
    const uint32_t devCh   = mixFormat ? mixFormat->nChannels : 2;
    const bool     devIsFloat = mixFormat &&
        (mixFormat->wFormatTag == WAVE_FORMAT_IEEE_FLOAT ||
         (mixFormat->wFormatTag == WAVE_FORMAT_EXTENSIBLE &&
          reinterpret_cast<WAVEFORMATEXTENSIBLE*>(mixFormat)->SubFormat
              == KSDATAFORMAT_SUBTYPE_IEEE_FLOAT));
    {
        char buf[160];
        std::snprintf(buf, sizeof(buf),
                      "render: mixFormat rate=%u ch=%u float=%d wFormatTag=0x%x",
                      devRate, devCh, devIsFloat ? 1 : 0,
                      mixFormat ? mixFormat->wFormatTag : 0);
        audio_log(buf);
    }
    if (!devIsFloat) {
        audio_log("render: mix format not IEEE_FLOAT — playback disabled");
        CoTaskMemFree(mixFormat);
        cleanup();
        return;
    }

    REFERENCE_TIME bufDuration = 60 * kRefTimesPerMs;
    hr = client->Initialize(AUDCLNT_SHAREMODE_SHARED,
                            AUDCLNT_STREAMFLAGS_EVENTCALLBACK,
                            bufDuration, 0, mixFormat, nullptr);
    if (FAILED(hr)) {
        char buf[128];
        std::snprintf(buf, sizeof(buf), "render: Initialize failed (0x%08lx)", hr);
        audio_log(buf);
        CoTaskMemFree(mixFormat); cleanup(); return;
    }

    UINT32 bufferFrames = 0;
    client->GetBufferSize(&bufferFrames);
    client->SetEventHandle(event);
    hr = client->GetService(__uuidof(IAudioRenderClient),
                            reinterpret_cast<void**>(&render));
    if (FAILED(hr)) {
        char buf[128];
        std::snprintf(buf, sizeof(buf), "render: GetService failed (0x%08lx)", hr);
        audio_log(buf);
        CoTaskMemFree(mixFormat); cleanup(); return;
    }
    audio_log("render: started");

    // Prime with silence so render doesn't underrun before audio arrives.
    BYTE* primeData = nullptr;
    if (SUCCEEDED(render->GetBuffer(bufferFrames, &primeData))) {
        std::memset(primeData, 0, static_cast<size_t>(bufferFrames) * devCh * sizeof(float));
        render->ReleaseBuffer(bufferFrames, 0);
    }
    client->Start();

    while (_running.load()) {
        const DWORD wait = WaitForSingleObject(event, 200);
        if (wait != WAIT_OBJECT_0 && wait != WAIT_TIMEOUT) break;

        UINT32 padding = 0;
        client->GetCurrentPadding(&padding);
        UINT32 framesAvailable = bufferFrames - padding;
        if (framesAvailable == 0) continue;

        const uint32_t neededAt48k = framesAvailable * kSampleRate / devRate;
        // Pull frames from each session's jitter buffer and mix.
        std::vector<float> mix(neededAt48k, 0.f);
        size_t produced = 0;

        // Iterate over a snapshot of session pointers, then mix without holding
        // the outer map mutex.
        std::vector<PerSession*> sessions;
        {
            std::lock_guard<std::mutex> lk(_sessionsMu);
            sessions.reserve(_sessions.size());
            for (auto& kv : _sessions) sessions.push_back(kv.second.get());
        }
        // Snapshot per-session gains under one short lock so we don't hold
        // the gains mutex during the audio render loop.
        std::unordered_map<uint32_t, float> userGainsCopy;
        {
            std::lock_guard<std::mutex> lk(_userGainsMu);
            userGainsCopy = _userGains;
        }
        // Map session -> PerSession* and remember the session-id for gain lookup.
        std::vector<std::pair<uint32_t, PerSession*>> sessionList;
        {
            std::lock_guard<std::mutex> lk(_sessionsMu);
            sessionList.reserve(_sessions.size());
            for (auto& kv : _sessions) sessionList.emplace_back(kv.first, kv.second.get());
        }

        while (produced < neededAt48k) {
            bool any = false;
            const size_t take = std::min<size_t>(kFrameSamples, neededAt48k - produced);
            for (auto& [sid, s] : sessionList) {
                std::lock_guard<std::mutex> lk(s->mu);
                if (s->queue.empty()) continue;
                const auto& frame = s->queue.front();
                auto gainIt = userGainsCopy.find(sid);
                const float g = (gainIt == userGainsCopy.end()) ? 1.0f : gainIt->second;
                for (size_t i = 0; i < take; ++i) {
                    mix[produced + i] += frame[i] * g;
                }
                if (frame.size() <= take) {
                    s->queue.pop_front();
                } else {
                    auto& mutFrame = const_cast<std::vector<float>&>(frame);
                    mutFrame.erase(mutFrame.begin(), mutFrame.begin() + take);
                }
                any = true;
            }
            if (!any) break;
            produced += take;
        }
        // Apply output gain + soft clip.
        const float gain = _outputGain.load();
        for (float& s : mix) {
            float v = s * gain;
            if (v > 1.f) v = 1.f;
            if (v < -1.f) v = -1.f;
            s = v;
        }

        // Upmix/resample to device.
        std::vector<float> outBuf;
        upmix_and_resample(mix.data(), mix.size(), kSampleRate, outBuf,
                           devRate, devCh);
        const UINT32 outFrames = static_cast<UINT32>(outBuf.size() / devCh);
        const UINT32 writeFrames = std::min(framesAvailable, outFrames);

        BYTE* data = nullptr;
        hr = render->GetBuffer(writeFrames, &data);
        if (SUCCEEDED(hr) && data) {
            if (_deafened.load()) {
                std::memset(data, 0, static_cast<size_t>(writeFrames) * devCh * sizeof(float));
            } else {
                std::memcpy(data, outBuf.data(),
                            static_cast<size_t>(writeFrames) * devCh * sizeof(float));
            }
            render->ReleaseBuffer(writeFrames, 0);
        }
    }

    CoTaskMemFree(mixFormat);
    cleanup();
}
