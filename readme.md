# Sysdelta

This is a tool of mine used to calculate the difference for a file in time.
Specifically system files in /sys which consists of only numbers. 
But any file which consist of numbers (and only numbers) works.

It works by first caching the content of the file the first time it is runned 
with a new configuration and on later runs compares the 
differences between whats cached and whats the source. 
Then source get's cached again. It can also calculate timedelta.

I used sysdelta it to keep track of network speeds.
It's a good enough indicator for how fast it's network speed up and down is.
It's output is compairable to bottom (a system monitor tool) but rarly the same,
possibly due to diffrent timing in sampling speeds.

Here is the snippet:
```sh
sysdelta "rx %8l tx %8l%n" /sys/class/net/wlo1/statistics/rx_bytes /sys/class/net/wlo1/statistics/tx_bytes
```

Keep in mind that you're /sys folder might differ from mine.

## Requirements:
free pascal and make.

## Installation:
`make install`

This will install sysdelta to "$HOME/.local/bin".

## About

I created this program as to learn a bit of pascal and I can now say that it's
quite nice for it's age.
