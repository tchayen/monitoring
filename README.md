# Monitoring service

Experimental thing to run a monitoring service with visualisations using Grafana
and storing the data (for now) using Graphite and Carbon.

## Running

- create a new vps (tested on Digital Ocean with 5$/mo machine)
- `ssh` there
- paste content of `install.sh`
- save as some `file`
- chmod +x `file`
- `./file`
- ...?

## TODO

- find out how to connect Graphite as a data source for Grafana
- automate the data source step, preferably create `*.json` with Grafana dashboard
