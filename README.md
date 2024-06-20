# COAR Vocabularies

The [COAR Vocabularies](https://vocabularies.coar-repositories.org/) are a standardised way to describe some aspects of content held in Open Access repositories.

They are being used in a variety of metadata profiles such as [RIOXX3](https://www.rioxx.net/profiles/).

In this repository are a set of resources to create relevent EPrints files for the vocabularies, using the N-triples representation of each vocabulary e.g. 
https://vocabularies.coar-repositories.org/version_types/1.1/version_types.nt

This can output:
- a namedset file for each vocabulary
- a language specific phrase file for each vocabulary
- [maybe at some point...] a map of URIs/phrases to be included in an XSLT

## Processing the SKOS (WIP)

__NOTE: CURRENTLY THIS IS NON-STANDARD! Running a bin script from epm directory!!!__

Each N-Triples SKOS file contains multiple language variations. Not all of these are relevant to a given repository.

I'm still working out the best way to deploy these to a repository. The namedsets files are common to all languages.

One option is to cache the lang files in a 'sources' directory and have an EPM script copy relevant ones into the appropriate location.

Currently running:

`bin/process_coar_vocabs.pl --cached-file-dir=files/sources/clean`

will output files into `files/output/...`

### References

- A COAR plugin already exists for EPrints which maps some values, and contains a lot of stuff in a config file: https://bazaar.eprints.org/422/
- SKOS processing is based on https://gist.github.com/nichtich/769542/978b246c2d54b6e118d53977b8c5d0981ffa9ca2

### Issue with N-Triples files (2024-06-17)

Currently there is an issue with the online versions of the N-Triples files where most of the data is repeated, and the second instances are not correctly encoded.

An empty line delineates the good/bad sections, except for the creator/title/description of the vocab that appear at the end, which are not duplicated, but are incorrectly encoded.
Currently included in this repo are the original versions from the COAR website - saved in the `files/sources` directory, and some cleaned-up versions in `files/sources/clean`.

To clean the files in `vim`:
- search for an empty line `/^$` <kbd>enter</kbd> and mark it e.g. `ma` <kbd>enter</kbd>
- go to the bottom of the file `:$` <kbd>enter</kbd>
- Search for lines that don't match 'scheme' `/^\(.*scheme\)\@!.*$` <kbd>enter</kbd>. Search backwards using <kbd>N</kbd> 
- from the last line that doesn't match 'scheme', type `d'a` <kbd>enter</kbd>. This should remove all the lines that are badly encoded.
- The creators may have incorrectly encoded characters in them. To search for these, type `/[^\d0-\d127]` <kbd>enter</kbd>. This will find non-ASCII characters.
- ... I haven't found a sensible way to replace all the matched characters with their respctive `\u[code]`. The manual process is:  
move the cursor to the left of the character. Type `ga` <kbd>enter</kbd> . The hex code for the character should be displayed in the status bar. Insert '\u' followed by the uppercase representation of the code.

The vocabulary creators aren't actually included in the generated phrase files, but having a complete 'fixed' version of the file hopefully means this will all work when the online versions are resolved.
