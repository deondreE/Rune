#!/bin/bash

glslangValidator -V text.vert.glsl -o text.vert.spv
glslangValidator -V text.frag.glsl -o text.frag.spv
glslangValidator -V solid.vert.glsl -o solid.vert.spv
glslangValidator -V solid.frag.glsl -o solid.frag.spv
echo "Shaders COmpiled"
