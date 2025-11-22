#!/bin/bash

zig build 

sudo ./zig-out/bin/test_add_delete_addr
sudo ./zig-out/bin/test_add_delete_route
