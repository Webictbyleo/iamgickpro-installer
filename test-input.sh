#!/bin/bash

# Test script to debug user input issue

echo "Testing user input..."
echo
echo -n "Please type 'y' and press Enter: "
read -r response
echo "You entered: '$response'"

if [[ "$response" =~ ^[Yy] ]]; then
    echo "Input detected correctly!"
else
    echo "Input was not 'y'"
fi
