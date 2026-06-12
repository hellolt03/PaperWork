# DRLLog

## How to run

Run the default BGL workflow. The script trains a DQN model first if the target
model file does not exist, then runs prediction.

```powershell
cd D:\PaperWork\DRLLog
python DRLLog.py
```

## Prediction only

Use this when a model file already exists for the configured epoch count.

```powershell
$env:DRLLOG_MODE='predict'
python DRLLog.py
```

By default, the script uses `DRLLOG_EPOCHS=5`, so prediction expects this model:

```text
model_BGL/2024.1.10/target_q_network_epoch5_action1_r50.pt
```

## Change training size

The training run can be controlled with environment variables:

```powershell
$env:DRLLOG_EPOCHS='2'
$env:DRLLOG_MAX_TRAIN_SESSIONS='200'
$env:DRLLOG_BATCH_SIZE='64'
python DRLLog.py
```

Available variables:

- `DRLLOG_EPOCHS`: number of training epochs. Default: `5`.
- `DRLLOG_MAX_TRAIN_SESSIONS`: maximum number of BGL training sessions to use. Default: `20000`. Set to `all` for the full training set.
- `DRLLOG_BATCH_SIZE`: replay-buffer batch size. Default: `2048`.
- `DRLLOG_MODE`: `train_predict`, `train`, or `predict`. Default: `train_predict`.

## Environment

Tested locally with:

- Python 3.13
- PyTorch
- NumPy

On Windows, `DRLLog.py` sets `KMP_DUPLICATE_LIB_OK=TRUE` automatically to avoid
the duplicate OpenMP runtime error that can appear when importing PyTorch.

## Data and outputs

The default run uses the BGL files below:

- Training data: `data_BGL/wcl/session_train410.pkl`
- Normal test data: `data_BGL/wcl/session_test_normal410.pkl`
- Abnormal test data: `data_BGL/wcl/session_test_abnormal410.pkl`
- Final-state set: `data_BGL/final_states_set.pkl`
- Model output directory: `model_BGL/2024.1.10/`

Training writes model files like this:

```text
model_BGL/2024.1.10/target_q_network_epoch5_action1_r50.pt
```

Note: training updates `data_BGL/final_states_set.pkl`. This is part of the
current script behavior.
