# Stronghold

Baseline for NFTs

NFTs are backed by an ever-growing reserve of tokens.

## Existing Components
- floor pool: absorbs all supply at given price, issues loans
- trade pool: main trading curve, main fee generator
- anchor pool: tracks trade pool's twap to provide deeper liq right below the avg trading price
- fixed-term loans: free leverage

## Future Components

supply caps for both to prevent griefing
- lock-in sell price: put options
- borrow NFTs against TWAP: shorting