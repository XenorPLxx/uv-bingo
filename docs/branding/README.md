# Discord avatar

[discord-avatar.png](discord-avatar.png) is the finished opaque 1254 × 1254 PNG for the app icon and bot avatar. Its four tiles use the website's purple/cyan palette and the symbols U, V, ? and X. The artwork fits a circular crop.

Generated with the built-in image_gen tool. The complete prompt is saved in [avatar-prompt.txt](avatar-prompt.txt).

To apply it to the application identified by a local environment file:

```sh
set -a
source .envrc.staging
set +a
bundle exec ruby script/configure_discord_avatar.rb
```

The script verifies the application and bot identities, updates their images, and reads them back. It uses Discord's [Edit Current Application](https://docs.discord.com/developers/resources/application#edit-current-application) and [Modify Current User](https://docs.discord.com/developers/resources/user#modify-current-user) endpoints.
