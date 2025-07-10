# runai log collector

a propietary script for collecting logs using kubectl, and a general info dump for debugging and investigating issues in runai environments.

## `runai` namespace:

file tree:

```
runai-logs-07-07-2025_14-30
├── cm_runai-public.yaml
├── engine-config.yaml
├── helm_charts_list.txt
├── helm-values_runai-cluster.yaml
├── logs
│   ├── <POD_NAME>_<CONTAINER_NAME>.log
│   ├── ...
├── node-list.txt
├── pod-list_runai.txt
└── runaiconfig.yaml
```

## `runai-backend` namespace

file tree:

```
runai-backend-logs-07-07-2025_14-31
├── helm-values_runai-backend.yaml
├── logs
│   ├── <POD_NAME>_<CONTAINER_NAME>.log
│   ├── ...
└── pod-list_runai-backend.txt
```