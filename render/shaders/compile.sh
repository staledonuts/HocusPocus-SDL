#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
glslc -fshader-stage=vert "$DIR/present.vert.glsl" -o "$DIR/present.vert.spv"
glslc -fshader-stage=frag "$DIR/present.frag.glsl" -o "$DIR/present.frag.spv"
glslc -fshader-stage=vert "$DIR/sprite.vert.glsl"  -o "$DIR/sprite.vert.spv"
glslc -fshader-stage=frag "$DIR/sprite.frag.glsl"  -o "$DIR/sprite.frag.spv"
echo "Compiled SPIR-V shaders in $DIR"
