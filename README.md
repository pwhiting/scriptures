This repo contains scripts to embed scriptures and search them

ensure you've exported your OPEN_API_KEY env variable prior to running

If you want to do your own embeddings clone https://github.com/bcbooks/scriptures-json and for each
book you want to embed type:
./embed [book.json]

For the Doctrine and Covenants just type
./embed-dandc
(it has a unique structure.)

Note that it will create the cromadb in whatever directory you issue the command in.
The Choroma db will be named scriptures_db. 

If you want to skip the embedding steps/cost just download this file:
http://dugg.in/s.zip 
and  unzip it.

It is 450M. Be patient.

To run any of the searches make sure you are in the same directory as the scriptures_db directory, and just
type:

./search am I a child of God

It will combine all the words on the command line into the query.

If you want to use punctuation put it in quotes

./search "am I a child of God?"

or you can just type ./search and enter the terms on stdin followed by ctrl-D

combine does all the different methods and overwrites output.xslx with the results for comparison.

The search methods supported are:
search - normal similarity search
search-mmr - max marginal relevance search, should have more diverse matches
search-ai - uses AI to refiine your search terms
search-language - embeds in English, Spanish, and Mandrin and uses the average embedding to search



