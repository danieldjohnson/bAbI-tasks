#!/usr/bin/env bash
luarocks make babitasks-scm-1.rockspec
set -e
mkdir -p output
rm output/*
for i in `seq 1 20`
do
    babi-tasks $i 1000 output/task_${i}_train.txt --knowledge_graph true --limit_story 25
    babi-tasks $i 1000 output/task_${i}_valid.txt --knowledge_graph true --limit_story 25
done