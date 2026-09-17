# Stay22 Flutter SDK integration prompt

Give this file to a coding assistant with your Stay22 partner ID (`aid`).

````text
Integrate the Stay22 Flutter SDK into this Flutter app.

Fetch Stay22's current docs. Do not rely on remembered Stay22 APIs.

1. https://dev.stay22.com/llms.txt (Mobile SDK section)
2. https://dev.stay22.com/docs/mobile-sdk.md
3. Append `.md` to any other page URL. Start with
   https://dev.stay22.com/docs/mobile-sdk/quick-start.md
4. After you know the version you installed, read
   https://dev.stay22.com/docs/mobile-sdk/changelog/flutter.md
5. Do not invent configuration flags, suppression ranges, or cookie
   behavior. If a page and the installed SDK disagree, that version's
   changelog wins.
6. If a docs page points at this repository's README for
   `UNUserNotificationCenter.delegate`, follow that README. Do not
   invent a second copy of that step.

Partner ID (`aid`): <AID>
````
