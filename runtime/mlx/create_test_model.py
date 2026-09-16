"""Generate CC0 synthetic tiny Llama weights for real, download-free engine tests."""
import json
from pathlib import Path
import sys
import mlx.core as mx
import mlx.nn as nn
from mlx.utils import tree_flatten
from mlx_lm.models.llama import Model, ModelArgs
from tokenizers import Tokenizer
from tokenizers.models import WordLevel
from tokenizers.pre_tokenizers import Whitespace

root = Path(sys.argv[1])
root.mkdir(parents=True, exist_ok=False)
config = dict(model_type='llama', hidden_size=64, num_hidden_layers=1,
              intermediate_size=128, num_attention_heads=4, num_key_value_heads=4,
              rms_norm_eps=1e-5, vocab_size=32, rope_theta=10000.0)
mx.random.seed(42)
model = Model(ModelArgs.from_dict(config))
nn.quantize(model, group_size=32, bits=4)
mx.eval(model.parameters())
mx.save_safetensors(str(root / 'model.safetensors'), dict(tree_flatten(model.parameters())))
config['quantization'] = dict(group_size=32, bits=4)
(root / 'config.json').write_text(json.dumps(config))
vocab = {'[UNK]': 0, 'Reply': 1, 'with': 2, 'OK': 3, '.': 4}
vocab.update({f'token{i}': i for i in range(5, 32)})
tokenizer = Tokenizer(WordLevel(vocab, unk_token='[UNK]'))
tokenizer.pre_tokenizer = Whitespace()
tokenizer.save(str(root / 'tokenizer.json'))
(root / 'LICENSE').write_text('CC0-1.0: synthetic random weights and tokenizer created for WTM tests.\n')
