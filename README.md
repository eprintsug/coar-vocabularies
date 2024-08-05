# COAR Vocabularies

The [COAR Vocabularies](https://vocabularies.coar-repositories.org/) are a standardised way to describe some aspects of content held in Open Access repositories.
They are organised using [SKOS (Simple Knowledge Organisation System)](https://www.w3.org/TR/skos-reference/).

The vocabulatries are being used in a variety of metadata profiles such as [RIOXX3](https://www.rioxx.net/profiles/).

In this Git repository are a set of resources to create relevent EPrints files for the vocabularies, using the N-triples representation of each vocabulary e.g. 
https://vocabularies.coar-repositories.org/version_types/1.1/version_types.nt

The script will output:
- a namedset file for each vocabulary
- language specific phrase files for each vocabulary, in each language represented in the N-triple file.
- [maybe at some point...] a map of URIs/phrases to be included in an XSLT for the OAI-PMH interface.

## Processing the SKOS 

__NOTE: CURRENTLY THIS IS NON-STANDARD! Running a bin script from epm directory!!!__

Each N-Triples SKOS file contains multiple language variations. Not all of these are relevant to a given repository.

I'm still working out the best way to deploy these to a repository. The namedsets files are common to all languages.

One option is to cache the lang files in a 'sources' directory and have an EPM script copy relevant ones into the appropriate location.

Currently running:

`bin/process_coar_vocabs.pl`

will output files into `files/output/cfg/namedsets/...` and `files/output/cfg/lang/[LANG]/phrases/...`.

### References

- COAR Vocabularies site: https://vocabularies.coar-repositories.org/
- A COAR plugin already exists for EPrints which maps some values, and contains a lot of stuff in a config file: https://bazaar.eprints.org/422/
- SKOS processing is based on https://gist.github.com/nichtich/769542/978b246c2d54b6e118d53977b8c5d0981ffa9ca2

