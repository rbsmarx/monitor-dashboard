#!/bin/bash
for i in $(seq 1 6); do
  /Monitoramento/monitor.sh >> /Monitoramento/logs/cron.log 2>&1
  sleep 5
done
