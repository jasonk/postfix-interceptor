# Postfix Interceptor #

This is a configuration for a postfix server that we use primarily for
development environments, but can also be helpful in production for
some scenarios.

What it does is to provide a server that other services can use as
their SMTP server for delivering mail, and then make it easy for you
to write scripts that can modify or filter that mail before it gets
delivered to the recipient.

If you have services that are sending mail and you can configure them
to use a different SMTP server, then you can use this to intercept the
mail they send and modify at as needed.

Some examples of things I have used this for in the past:

 * Adding a footer to all outgoing mail from services in a dev/test/qa
   environment to let the recipient know that it came from a dev/test/qa
   environment.
 * Filtering messages from a dev/test/qa environment to prevent them
   from being delivered to real users who would have no idea what to
   do with them.
 * Alerting the `From:` address for the messages from some services to
   make them easier to filter.
 * Changing the content of "canned" messages from services where you
   can't control the templates being used.

## Setup ##

To use this, you will need a postfix server running in the appropriate
environment. Getting that setup and running is up to you, but once you
have it this is the configuration you need to add to it.

First off, I strongly recommend using a dedicated user for running
these scripts, for safety and security.

The first thing you want to configure in postfix is the "relay host".
This is the server that postfix will use to deliver mail when it is
done with it.

Lets say you want to intercept the mail being sent by a service
running on your network that currently uses your main mail server
`mail.example.com` as it's main SMTP server, and `backup.example.com`
as a secondary.

What you want to do is configure the `main.cf` file on your new
postfix server to include `relayhost=mail.example.com` and
`smtp_fallback_relay=backup.example.com`. Then you would configure the
service to use this new postfix server instead, essentially putting it
like a proxy between the service and the real mail server.

The `smtp_fallback_relay` setting is optional, if you only have one
upstream mail server you can just ignore it.  Also, don't forget that
if you are using an IP address instead of a DNS name for these
settings, you have to bracket it: `relayhost=[192.168.1.10]`.

Next you need to add the interceptor to your `master.cf` file:

```
# service type private? unprivileged? chroot? wakeup maxproc command
interceptor unix - n n - 32 pipe flags=Rq user=interceptor
    argv=/usr/sbin/interceptor-filter.sh ${sender} ${recipient}
```

Change the `/usr/sbin/interceptor-filter.sh` to the path where you
copied the `interceptor-filter.sh` file from this directory.

The `32` in this line is the limit of how many filter processes can
be run at once. You can increase that if you have a lot of mail to
process and the computing power needed to process it, or you can
decrease it if you end up overloading the server. We're using 32, but
the best value is largely determined by the resources of the server
you are running it on and the requirements of the scripts you are
running.

Next find the `smtp` line in the `master.cf` file and add
`-o content_filter=interceptor:dummy`, like so:

```
smtp      inet  ...other stuff here, do not change...   smtpd
    -o content_filter=interceptor:dummy
```

## How This Works ##

The short version: The postfix server accepts mail via SMTP just like
any other mail server, runs it through a script that can modify it,
and then delivers it through your normail mail server.

The long version:

All incoming smtp mail is received by the postfix `smtpd` daemon,
which adds the `content_filter` flag to the mail to override the
default mail routing and instruct postfix to pass the message to the
`interceptor` service for handling.

After adding the `content_filter` flag, the `smtpd` daemon passes the
message to the `cleanup` daemon, which adds the message to the
`incoming` queue and informs the `qmgr` daemon of it's arrival.

The `qmgr` daemon manages the processing of messages in the queue,
For messages that have the `content_filter` flag set, the `qmgr` will
spawn `pipe` processes as necessary to handle the messages.

The `pipe` process will get messages from the `qmgr` daemon to
process, and will run the `interceptor-filter.sh` script to
process it.

When the `interceptor-filter.sh` script runs, it creates a temporary
working directory and creates a bunch of files in that directory. It
then looks for a suitable script to run based on the sender of the
message.

It normalizes the sender address by replacing all non-alphanumeric
characters with dashes, and then looks in the
`/etc/postfix/interceptors` directory for a script with that name.
If it doesn't find one it looks to see if there is a script named
`default` and uses that one instead.

The files in the working directory include the following, which the
interceptor can modify in order to alter the message that is sent on
to the next stage of the mail delivery process:

 * `sender.txt` - The sender email address. You can change this to
   alter the envelope sender of the message if you need to do that.

 * `recipients.txt` - The recipient email addresses, one per line.
   You can remove recipients from this file to prevent them from
   receiving the message, or add recipients to deliver the message to
   additional recipients. If you remove this file entirely, or leave
   it empty, the message will be discarded.

 * `message.txt` - The message contents. You can modify this file
   to change the body and/or the headers of the message.

 * `subject.txt` - The message subject. This is separated out just
   because this was one of the things I commonly need to change in
   these kinds of filters. Note that if you change this file the
   subject of the message will be updated, even if you also changed
   the subject header directly in the `message.txt` file.

 * `content.txt` - The content of the message, with the headers
   removed.

 * `headers.txt` - The headers of the message, with the body removed.

Important notes:

 * Changes to the `sender` or `recipient` files only affect the
   message envelope, and will not change the `To`/`From` headers of
   the message. This means that if you want to change the sender and
   have it reflected in the `From` line you need to update the
   `headers.txt` file or `message` file also.
 * You can change the body of the message by changing either
   `message.txt` or `content.txt`, and you can change the headers by
   modifying either `message.txt` or `headers.txt`, but you should
   pick one method and stick with it.  If you modify `content.txt` or
   `headers.txt` then any changes to `message.txt` will be discarded.
 * The directory also includes a `checksums.txt` file that you should
   these files, which you should not change or things will probably
   break.

If the interceptor script exits successfully (or if no script was
found), the filter will reassemble the updated message and envelope.
If either the sender or recipient file are missing or empty then the
message will be discarded.

If the message and envelope are successfully reassembled, the filter
will call the `sendmail` command to deliver the message to the next
stage of the mail delivery process. At that point postfix will take
over and deliver the message to the configured `relayhost`.

If the interceptor script exits with an error, the filter will exit
with a `TEMPFAIL` exit code, which causes the `qmgr` to requeue the
message to try again later.  This means you need to keep any eye on
the mail queue to make sure that messages are not getting stuck due
to a broken filter.

## Author ##

Copyright 1997 Jason Kohles <email@jasonkohles.com> http://www.jasonkohles.com/
