# Speech Tools

tk provides private, local tools for turning speech into text and text into speech.

## Language

**Speech profile**:
A user-selectable balance of speed, quality, storage, and memory use for either Dictation or Read Aloud. Technical model names are secondary details.
_Avoid_: Model, engine, or preset as the user-facing name for this choice

**Dictation profile**:
A Speech profile used to turn recorded speech into text.
_Avoid_: STT model, transcription model

**Reading profile**:
A Speech profile used to turn selected text into spoken audio.
_Avoid_: TTS model, voice model

**Downloaded profile**:
An optional Speech profile whose complete model file has passed verification and is available on this Mac. Downloading a profile does not select it.
_Avoid_: Cached model, installed model

**Selected profile**:
The Speech profile a person intends tk to use for the next Dictation or Read request. Selection is preserved when that profile is unavailable, and is independent of whether another profile has been downloaded.
_Avoid_: Active model, default model

**Unavailable profile**:
A Speech profile that cannot currently serve a request on this Mac. If selected, the choice remains selected.
_Avoid_: Fallen-back profile, disabled profile
