import time
import os
import sys

print("Oracle Keep Alive service started. Targeting 12-14% CPU load on 1 core...")
sys.stdout.flush()

while True:
    start = time.perf_counter()
    # Busy loop for 13ms (13% of 100ms)
    while time.perf_counter() - start < 0.013:
        # Perform simple math to consume CPU
        x = 12345 * 54321
    # Sleep for 87ms
    time.sleep(0.087)
