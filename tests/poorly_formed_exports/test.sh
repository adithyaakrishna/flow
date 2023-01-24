#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# shellcheck disable=SC2094

echo "FLOW STATUS:"

assert_errors "$FLOW" status

echo "FLOW CHECK-CONTENTS:"

assert_errors "$FLOW" check-contents bad-named-export.js < bad-named-export.js
