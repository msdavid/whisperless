"""Diagnostic: offline decode of a wav on the same engine (bypasses streaming).
Usage: .venv/bin/python offline_probe.py <wav> [language]   (run from the R2T2 checkout)
"""
import sys
import librosa
from r2t2 import R2T2ASRModel

if __name__ == "__main__":
    wav_path = sys.argv[1] if len(sys.argv) > 1 else "resources/test.wav"
    lang = sys.argv[2] if len(sys.argv) > 2 else "English"
    asr = R2T2ASRModel.LLM(model="models/Confucius4-R2T2", gpu_memory_utilization=0.55,
                           max_model_len=8192, max_num_batched_tokens=2048, max_new_tokens=4096)
    wav, sr = librosa.load(wav_path, sr=16000, mono=True)
    r = asr.transcribe(audio=[(wav, 16000)], language=[lang], return_time_stamps=False)
    print("OFFLINE:", repr(r[0].text))