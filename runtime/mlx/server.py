"""WTM's frozen, single-model, offline MLX inference helper."""
import argparse
import json
import os
from pathlib import Path
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer


def local_model(path):
    root = Path(path)
    if not root.is_absolute() or root.is_symlink() or not root.is_dir():
        raise ValueError("An existing canonical local model directory is required")
    if root.resolve() != root:
        raise ValueError("Model directory must be canonical")
    for name in ('config.json', 'tokenizer.json'):
        file = root / name
        if file.is_symlink() or not file.is_file():
            raise ValueError("Required local model resource is missing")
    config_path = root / 'config.json'
    if config_path.stat().st_size > 2 * 1024 * 1024:
        raise ValueError("Model config exceeds limit")
    config = json.loads(config_path.read_text())
    if not isinstance(config, dict) or any(key in config for key in ('model_file', 'auto_map')):
        raise ValueError("Custom model code is unsupported")
    weights = list(root.glob('model*.safetensors'))
    if not weights or any(path.is_symlink() or not path.is_file() for path in weights):
        raise ValueError("Local model weights are missing")
    return root


def deny_external_actions(event, args):
    if event in ('socket.connect', 'socket.getaddrinfo', 'subprocess.Popen', 'os.system',
                 'os.exec', 'os.posix_spawn'):
        raise RuntimeError("External actions are disabled in the WTM MLX helper")
    if event == 'socket.bind' and args[1][0] != '127.0.0.1':
        raise RuntimeError("Only numeric loopback binding is allowed")


def serve(model_root, port):
    os.environ.update(HF_HUB_OFFLINE='1', TRANSFORMERS_OFFLINE='1',
                      HF_HUB_DISABLE_TELEMETRY='1', TOKENIZERS_PARALLELISM='false')
    sys.dont_write_bytecode = True
    sys.addaudithook(deny_external_actions)
    # No Hub-aware load(), AutoTokenizer or upstream multi-model HTTP server.
    import mlx.core as mx
    from mlx_lm.utils import load_model
    from tokenizers import Tokenizer
    model, _ = load_model(model_root, trust_remote_code=False)
    tokenizer = Tokenizer.from_file(str(model_root / 'tokenizer.json'))

    class Handler(BaseHTTPRequestHandler):
        def setup(self):
            super().setup()
            self.connection.settimeout(5)

        def log_message(self, *args):
            pass

        def reply(self, code, payload):
            body = json.dumps(payload).encode()
            self.send_response(code)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.path == '/health':
                self.reply(200, {'status': 'ok', 'protocol': 1})
            else:
                self.reply(404, {'error': 'Unsupported endpoint'})

        def do_POST(self):
            if self.path != '/completion':
                self.reply(404, {'error': 'Unsupported endpoint'})
                return
            try:
                lengths = self.headers.get_all('Content-Length', [])
                if len(lengths) != 1 or self.headers.get('Transfer-Encoding'):
                    raise ValueError('Invalid framing')
                length = int(lengths[0])
                if not 0 < length <= 4096:
                    raise ValueError('Invalid request size')
                body = self.rfile.read(length)
                if len(body) != length:
                    raise ValueError('Incomplete request')
                request = json.loads(body)
                if not isinstance(request, dict) or set(request) != {'prompt'}:
                    raise ValueError('Only a prompt is accepted')
                prompt = request['prompt']
                if not isinstance(prompt, str) or not 0 < len(prompt.encode()) <= 1024:
                    raise ValueError('Invalid prompt')
                tokens = tokenizer.encode(prompt).ids
                if not 0 < len(tokens) <= 256:
                    raise ValueError('Invalid token count')
                logits = model(mx.array([tokens]))
                token = int(mx.argmax(logits[0, -1]).item())
                content = tokenizer.decode([token], skip_special_tokens=False)
                self.reply(200, {'content': content, 'tokens_predicted': 1})
            except (ValueError, KeyError, TypeError, TimeoutError):
                self.reply(400, {'error': 'Invalid local inference request'})
            except Exception:
                self.reply(500, {'error': 'Local inference failed'})

    HTTPServer(('127.0.0.1', port), Handler).serve_forever()


def main():
    if not getattr(sys, 'frozen', False):
        sys.exit('Use the signed WTM MLX Runtime bundle.')
    parser = argparse.ArgumentParser()
    parser.add_argument('--model', required=True)
    parser.add_argument('--port', required=True, type=int)
    args = parser.parse_args()
    if not 1024 <= args.port <= 65535:
        parser.error('Port outside supported range')
    root = local_model(args.model)
    serve(root, args.port)


if __name__ == '__main__':
    main()
