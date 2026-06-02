+++
title = "TIL: Reading Gmail in Emacs with mu4e on macOS"
author = ["Yi-Ping Pan (Cloudlet)"]
description = "Setting up mu4e + mbsync with Gmail App Password on macOS — no OAuth2"
date = 2026-05-27
draft = false
[taxonomies]
  tags = ["emacs", "mu4e", "mbsync", "gmail", "macos"]
  categories = ["software-tooling"]
+++

> I like writing email in plain text and I wanted to read email without leaving Emacs.

Most guides I found either target Linux or go straight to OAuth2 — which involves registering a Google Cloud project, setting up credentials, and running a local token server. That felt like too much for something that should be simple.

Turns out App Password is enough, and the setup takes about 20 minutes.

[mu4e dashboard in Doom Emacs](/images/mu4e-dashboard.png)


## What is needed {#what-is-needed}

-   macOS
-   Emacs (I use [emacs-plus](https://github.com/d12frosted/homebrew-emacs-plus))
-   Gmail account with 2-Step Verification enabled


## Install mu and mbsync {#install-mu-and-mbsync}

```bash
brew install mu isync
```

`mu` is the mail indexer. `isync` provides `mbsync`, which syncs your mailbox over IMAP.


## Get a Gmail App Password {#get-a-gmail-app-password}

Gmail no longer allows plain password authentication over IMAP. You need an App Password.

1.  Go to [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords)
2.  Create a new one, name it `mbsync`
3.  You get a 16-character password — keep it, you'll need it once


## Configure mbsync {#configure-mbsync}

Create `~/.mbsyncrc`:

```ini
IMAPAccount gmail
Host imap.gmail.com
User your@gmail.com
PassCmd "security find-generic-password -s mbsync-gmail -a your@gmail.com -w"
AuthMechs PLAIN
TLSType IMAPS
CertificateFile /opt/homebrew/etc/ca-certificates/cert.pem

IMAPStore gmail-remote
Account gmail

MaildirStore gmail-local
SubFolders Verbatim
Path ~/Mail/gmail/
Inbox ~/Mail/gmail/Inbox

Channel gmail
Far :gmail-remote:
Near :gmail-local:
Patterns * ![Gmail]* "[Gmail]/Sent Mail" "[Gmail]/Trash" "[Gmail]/Drafts"
Create Both
Expunge Both
SyncState *
```

The `PassCmd` pulls the password from macOS Keychain at sync time — no plaintext passwords sitting in config files.


## Store the App Password in Keychain {#store-the-app-password-in-keychain}

```bash
security add-generic-password -s mbsync-gmail -a your@gmail.com -w
```

Paste the 16-character App Password when prompted. No spaces.


## First sync {#first-sync}

```bash
mkdir -p ~/Mail/gmail
mbsync -a
```

If you see `IMAP command 'AUTHENTICATE PLAIN' returned an error: AUTHENTICATIONFAILED` — the App Password is wrong. Delete it and try again:

```bash
security delete-generic-password -s mbsync-gmail
security add-generic-password -s mbsync-gmail -a your@gmail.com -w
```


## Index with mu {#index-with-mu}

```bash
mu init --maildir=~/Mail/gmail --my-address=your@gmail.com
mu index
```


## SMTP: sending mail {#smtp-sending-mail}

Create `~/.authinfo.gpg` for outgoing mail:

```ini
machine smtp.gmail.com login your@gmail.com password YOUR_APP_PASSWORD port 587
```

Encrypt it with GPG:

```bash
gpg --output ~/.authinfo.gpg --symmetric ~/.authinfo
rm ~/.authinfo
```

You can use the same App Password, or create a separate one named `smtp`.


## Emacs config (Doom) {#emacs-config--doom}

In `config.el`:

```elisp
(after! mu4e
  (setq mu4e-maildir "~/Mail/gmail"
        mu4e-get-mail-command "mbsync -a"
        mu4e-update-interval 300
        mu4e-compose-reply-to-address "your@gmail.com"
        mu4e-sent-folder "/[Gmail]/Sent Mail"
        mu4e-drafts-folder "/[Gmail]/Drafts"
        mu4e-trash-folder  "/[Gmail]/Trash"
        mu4e-refile-folder "/[Gmail]/All Mail"
        mu4e-compose-format-flowed nil
        message-send-mail-function #'smtpmail-send-it
        smtpmail-smtp-server "smtp.gmail.com"
        smtpmail-smtp-service 587
        smtpmail-stream-type 'starttls
        smtpmail-smtp-user "your@gmail.com"
        smtpmail-auth-credentials (expand-file-name "~/.authinfo.gpg")))
```

In `init.el`, enable the mu4e module:

```elisp
;; In init.el, find the :email section and enable mu4e with the +gmail flag:
:email
(mu4e +gmail)
```

Then `doom sync` and restart Emacs.


## Basic usage {#basic-usage}

| Key        | Action           |
|------------|------------------|
| `M-x mu4e` | Open mu4e        |
| `U`        | Sync and update  |
| `C`        | Compose new mail |
| `C-c C-c`  | Send             |
| `C-c C-d`  | Save draft       |
| `r`        | Reply            |
| `d`        | Mark as trash    |

No OAuth2, no token server, no Google Cloud project. Just App Password, Keychain, and authinfo.
