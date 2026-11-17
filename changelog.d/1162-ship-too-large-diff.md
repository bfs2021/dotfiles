ship.sh no longer refuses when GitHub says a PR diff is too large. It builds the diff locally from the base and head commits, so every lane check reads the same content.
