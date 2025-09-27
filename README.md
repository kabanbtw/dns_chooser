# 🚀 DNS Chooser for Arch Linux

A simple script to test the speed and reliability of popular DNS servers.  
It measures latency and packet loss for a list of DNS servers and outputs a ranking of the best performers.

⚠️ By default, the script only performs tests and does not modify system settings. Any changes must be applied manually via GUI or terminal.

## 📥 Installation

1. Clone the repository:

   ```bash
   git clone https://github.com/kabanbtw/dns_chooser.git
   cd dns_chooser
   ```

2. Make the script executable:

   ```bash
   chmod +x dns_chooser.sh
   ```

## ▶️ Usage

Run the script in the terminal:

```bash
./dns_chooser.sh
```

Or specify the full path:

```bash
/path/to/dns_chooser.sh
```

## 📝 Notes

- Compatible with Arch Linux and similar distributions.
- Requires `ping` and `dig` commands. Ensure the `bind` package is installed:

  ```bash
  sudo pacman -S bind
  ```

- The script performs tests only and does not modify system settings.

## 📬 Contact

✉️ Email: epidermis_essential@proton.me

💬 Discord Server: [Join here](https://discord.gg/2bFvWXRS6u)

## 📜 License

[MIT License](LICENSE)
