// mumble_bridge.h
//
// C ABI between the Flutter app (Dart FFI) and the native bridge DLL that
// wraps libmumble + WASAPI + RNNoise + the audio mixer.
//
// Conventions:
//   - All strings are UTF-8, null-terminated.
//   - All buffers are (pointer, length).
//   - Functions returning int return 0 on success, a positive error code on
//     failure. Negative values are reserved.
//   - The bridge owns its own threads (networking and audio). UI code calls
//     these functions from the Dart main isolate.
//   - Asynchronous events (channel changes, user state, text messages, audio
//     levels, talking state, etc.) are delivered to a Dart SendPort registered
//     with mb_set_event_port. Each event is a UTF-8 JSON string; the Dart side
//     parses and dispatches.
//   - There is one client instance per process. No multi-client support.

#ifndef MUMBLE_BRIDGE_H
#define MUMBLE_BRIDGE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#  if defined(MUMBLE_BRIDGE_EXPORTS)
#    define MB_API __declspec(dllexport)
#  else
#    define MB_API __declspec(dllimport)
#  endif
#else
#  define MB_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// ---------------------------------------------------------------------------
// Error codes
// ---------------------------------------------------------------------------

typedef enum mb_result {
    MB_OK                  = 0,
    MB_ERR_NOT_INITIALIZED = 1,
    MB_ERR_ALREADY_INIT    = 2,
    MB_ERR_INVALID_ARG     = 3,
    MB_ERR_NETWORK         = 4,
    MB_ERR_TLS             = 5,
    MB_ERR_AUTH            = 6,
    MB_ERR_AUDIO_DEVICE    = 7,
    MB_ERR_INTERNAL        = 99
} mb_result;

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

// Initialize the bridge. Must be called once before anything else.
MB_API int mb_init(void);

// Tear down the bridge. Disconnects, stops audio, releases libmumble.
MB_API void mb_shutdown(void);

// Returns the bridge build version as a static string (no free needed).
MB_API const char* mb_version(void);

// Register the Dart SendPort that will receive event JSON strings.
// Pass 0 to unregister.
MB_API void mb_set_event_port(int64_t send_port_id);

// Dart_InitializeApiDL bootstrap: the Dart side must call this once with
// NativeApi.initializeApiDLData so we can post messages.
MB_API int mb_init_dart_api(void* dart_api_dl_data);

// ---------------------------------------------------------------------------
// Connection
// ---------------------------------------------------------------------------

typedef struct mb_connect_params {
    const char* host;       // hostname or IP literal (v4 or v6)
    uint16_t    port;       // typically 64738
    const char* username;
    const char* password;   // may be NULL
    // Client TLS cert (PEM). If both are NULL, no client cert is sent.
    const char* cert_pem;
    const char* key_pem;
    // Channel access tokens (NULL-terminated array of UTF-8 strings, or NULL).
    const char* const* tokens;
} mb_connect_params;

// Initiates a connection. Returns MB_OK if accepted for processing; the
// actual connection state arrives as a "connection_state" event.
MB_API int mb_connect(const mb_connect_params* params);

MB_API void mb_disconnect(void);

// ---------------------------------------------------------------------------
// Channel + user actions
// ---------------------------------------------------------------------------

MB_API void mb_join_channel(uint32_t channel_id);

// Send a text message to a channel (and optionally its tree).
MB_API void mb_send_text_channel(uint32_t channel_id, bool include_tree, const char* text);

// Send a text message to a specific user session.
MB_API void mb_send_text_user(uint32_t session_id, const char* text);

// Set/clear self-listening on a channel (one-way listen-in).
MB_API void mb_set_listen_channel(uint32_t channel_id, bool listen);

// ---------------------------------------------------------------------------
// Self state
// ---------------------------------------------------------------------------

MB_API void mb_set_self_mute(bool mute);
MB_API void mb_set_self_deaf(bool deaf);
MB_API void mb_set_self_comment(const char* comment);

// ---------------------------------------------------------------------------
// Voice transmission
// ---------------------------------------------------------------------------

typedef enum mb_tx_mode {
    MB_TX_CONTINUOUS = 0,
    MB_TX_VAD        = 1,
    MB_TX_PTT        = 2
} mb_tx_mode;

MB_API void mb_set_tx_mode(mb_tx_mode mode);

// For PTT: report the current pressed state of the bound key.
MB_API void mb_set_ptt_pressed(bool pressed);

// Install a system-wide low-level keyboard hook that drives PTT directly:
// pressing `vk_code` flips ptt-pressed true, releasing it flips to false.
// This bypasses RegisterHotKey (which doesn't report key-up events). Pass
// vk_code = 0 to uninstall any existing hook. Returns MB_OK on success.
MB_API int mb_install_ptt_hook(int vk_code);

// VAD threshold in [0,1]; higher = harder to trigger.
MB_API void mb_set_vad_threshold(float threshold);

// Hangover in ms: keep transmitting this long after voice ends.
MB_API void mb_set_voice_hold_ms(uint32_t ms);

// ---------------------------------------------------------------------------
// Audio I/O
// ---------------------------------------------------------------------------

// Returns a JSON array of devices: [{"id":"...", "name":"...", "default":bool}, ...]
// Caller must free with mb_free_string.
MB_API char* mb_list_input_devices(void);
MB_API char* mb_list_output_devices(void);

// Pass NULL to mean "system default".
MB_API int mb_set_input_device(const char* device_id);
MB_API int mb_set_output_device(const char* device_id);

// Gain in dB. 0 = unity.
MB_API void mb_set_input_gain_db(float db);
MB_API void mb_set_output_gain_db(float db);

// Per-user output gain in dB. 0 = unity. Persists across user state changes.
MB_API void mb_set_user_gain_db(uint32_t session_id, float db);

MB_API void mb_set_noise_suppression(bool enabled);

// Attenuate other users while you are talking, by `db` dB (negative = quieter).
MB_API void mb_set_attenuate_others_db(float db);

// Whether to use the Windows "communications" endpoint role for the mic and
// speakers. When true (default), Windows automatically ducks other apps'
// audio while we're using the device (matches Mumble / Discord / Teams).
// When false, we use the "console" endpoint role and don't trigger ducking.
// Changing this restarts the audio engine if it's running.
MB_API void mb_set_audio_ducking(bool duck);

// Opus encoder settings.
MB_API void mb_set_opus_bitrate(uint32_t bps);            // e.g. 24000..96000
MB_API void mb_set_opus_frames_per_packet(uint32_t n);    // 1..6 (10ms each)

// ---------------------------------------------------------------------------
// Whisper / shout
// ---------------------------------------------------------------------------

// Server-side voice target slots are 1..30. 0 = normal speak.
MB_API void mb_voice_target_clear(uint8_t target_id);
MB_API void mb_voice_target_add_users(uint8_t target_id,
                                      const uint32_t* session_ids, size_t count);
MB_API void mb_voice_target_add_channel(uint8_t target_id, uint32_t channel_id,
                                        bool include_subchannels, bool include_linked);

// Switch active voice target. 0 = normal speak.
MB_API void mb_use_voice_target(uint8_t target_id);

// ---------------------------------------------------------------------------
// Recording
// ---------------------------------------------------------------------------

typedef enum mb_record_format {
    MB_REC_WAV  = 0,
    MB_REC_OPUS = 1  // future
} mb_record_format;

typedef enum mb_record_mode {
    MB_REC_MIX        = 0,  // single stereo mixdown
    MB_REC_MULTITRACK = 1   // one file per user (future)
} mb_record_mode;

MB_API int  mb_recording_start(const char* file_path, mb_record_format fmt, mb_record_mode mode);
MB_API void mb_recording_stop(void);
MB_API bool mb_recording_active(void);

// ---------------------------------------------------------------------------
// Certificate management
// ---------------------------------------------------------------------------

// Generates a self-signed certificate. Returned strings are heap-allocated;
// free with mb_free_string. Out-params receive PEM-encoded cert and key.
// Returns MB_OK or an error code.
MB_API int mb_generate_self_signed_cert(const char* common_name,
                                        const char* email,
                                        char** out_cert_pem,
                                        char** out_key_pem);

// ---------------------------------------------------------------------------
// Allocation helpers
// ---------------------------------------------------------------------------

// Frees a string returned by any mb_* function that returns char*.
MB_API void mb_free_string(char* str);

#ifdef __cplusplus
}
#endif

#endif // MUMBLE_BRIDGE_H
