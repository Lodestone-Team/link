
## Setup Guide

### DNS

Choose a unique subdomain for this server.

We will continue this guide by assuming the domain `us1.lodestone.link` and the static ip address `123.123.123.123`

Create the following 2 DNS records:

| Type | Name  | Content         |
| ---- | ----- | --------------- |
| A    | us1   | 123.123.123.123 |
| A    | *.us1 | 123.123.123.123 |

### Setup
run the setup script