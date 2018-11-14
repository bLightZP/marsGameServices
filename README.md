# marsGameServices

I wrote this REST server as a backend for RGBquick:
https://play.google.com/store/apps/details?id=com.inmatrix.RGBquick

The server recieves player scores (in JSON format) and returns a JSON result with the player's position in a global leaderboard.

The server also provides an access point that returns the entire leaderboard as pure-text flat-database format (same format used when saving the database locally).

The submitted data is verified to be legitimate using a simple salted hash and by checking the client's user-agent.
