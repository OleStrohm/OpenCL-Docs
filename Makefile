# Copyright (c) 2013-2019 The Khronos Group Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

QUIET	    ?=
ASCIIDOC    ?= asciidoc
ASCIIDOCTOR ?= asciidoctor
XMLLINT     ?= xmllint
DBLATEX     ?= dblatex
DOS2UNIX    ?= dos2unix
RM	    = rm -f
RMRF	    = rm -rf
MKDIR	    = mkdir -p
CP	    = cp
GS_EXISTS   := $(shell command -v gs 2> /dev/null)
GITHEAD     = ./.git/logs/HEAD

# Target directories for output files
# HTMLDIR - 'html' target
# PDFDIR - 'pdf' target
# CHECKDIR - 'allchecks' target
OUTDIR	  := out
HTMLDIR   := $(OUTDIR)/html
PDFDIR	  := $(OUTDIR)/pdf

# PDF Equations are written to SVGs, this dictates the location to store those files (temporary)
PDFMATHDIR := $(OUTDIR)/equations_temp

# Set VERBOSE to -v to see what asciidoc is doing.
VERBOSE =

# asciidoc attributes to set.
# NOTEOPTS   sets options controlling which NOTEs are generated
# ATTRIBOPTS sets the api revision and enables MathJax generation, and
#	     the path to generate include files
# ADOCOPTS   options for asciidoc->HTML5 output
# Currently unused in CL spec
NOTEOPTS     = -a editing-notes
# Spell out RFC2822 format as not all date commands support -R
SPECDATE     = $(shell echo `date -u "+%a, %d %b %Y %T %z"`)

# Generate Asciidoc attributes for spec version and remark
# The dependency on HEAD is per the suggestion in
# http://neugierig.org/software/blog/2014/11/binary-revisions.html
ifeq ($(wildcard $(GITHEAD)),)
# If GITHEAD does not exist, don't include branch info.
SPECREVISION = Git tag information not available
SPECREMARK = Git branch information not available
else
# Expect the tag to be in the format MAJOR.MINOR-REVISION, e.g. 2.2-9.
# If your current commit is not a tag then a commit hash will be appended.
# If you have locally modified files then -dirty will be appended.
# Could use `git log -1 --format="%cd"` to get branch commit date
SPECREVISION = $(shell echo `git describe --tags --dirty`)
# This used to be a dependency in the spec html/pdf targets,
# but that's likely to lead to merge conflicts. Just regenerate
# when pushing a new spec for review to the sandbox.
SPECREMARK = from git branch: $(shell echo `git symbolic-ref --short HEAD`) \
	     commit: $(shell echo `git log -1 --format="%H"`)
endif

ATTRIBOPTS   = -a revnumber="$(SPECREVISION)" \
	       -a revdate="$(SPECDATE)" \
	       -a revremark="$(SPECREMARK)" \
	       -a stem=latexmath \
	       -a api=$(APIINCDIR)

# Currently not using custom asciidoctor macros
# ADOCEXTS     = -r $(CURDIR)/config/vulkan-macros.rb
ADOCEXTS     = -r $(CURDIR)/config/sectnumoffset-treeprocessor.rb
ADOCOPTS     = -d book $(ATTRIBOPTS) $(NOTEOPTS) $(VERBOSE) $(ADOCEXTS)

KATEXDIR     = ../katex
ADOCHTMLEXTS = -r $(CURDIR)/config/katex_replace.rb
ADOCHTMLOPTS = $(ADOCHTMLEXTS) -a katexpath=$(KATEXDIR) \
	       -a stylesheet=khronos.css -a stylesdir=$(CURDIR)/config

# The monkey patch for asciidoctor-pdf fixes issue #259
# (https://github.com/asciidoctor/asciidoctor-pdf/issues/259).
# I've submitted a pull request to fix it, once it goes into a gem release, we'll remove this.
ADOCPDFEXTS  = -r asciidoctor-pdf -r asciidoctor-mathematical \
	       -r $(CURDIR)/config/asciidoctor-pdf-monkeypatch.rb --trace
ADOCPDFOPTS  = $(ADOCPDFEXTS) -a mathematical-format=svg \
	       -a imagesoutdir=$(PDFMATHDIR)

# Where to put dynamically generated dependencies of the spec and other
# targets, from API XML. APIINCDIR is for the API interface includes.
# GENDEPENDS could have multiple dependencies.
APIINCDIR  = $(CURDIR)/inc
GENDEPENDS = $(APIINCDIR)/timeMarker

.PHONY: directories

# README.md is a proxy for all the katex files that need to be installed
katexinst: $(OUTDIR)/katex/README.md

$(OUTDIR)/katex/README.md: katex/README.md
	$(QUIET)$(MKDIR) $(OUTDIR)
	$(QUIET)$(RMRF)  $(OUTDIR)/katex
	$(QUIET)$(CP) -rf katex $(OUTDIR)

all: api env ext cxx c icdinst

allman: manhtmlpages

api: apihtml apipdf

env: envhtml envpdf

ext: exthtml extpdf

cxx: cxxhtml cxxpdf

c: chtml cpdf

icdinst: icdinsthtml icdinstpdf

html: apihtml envhtml exthtml cxxhtml chtml icdinsthtml

pdf: apipdf envpdf extpdf cxxpdf cpdf icdinstpdf

# Spec targets.
# There is some complexity to try and avoid short virtual targets like
# 'html' causing specs to *always* be regenerated.

src:
	@echo APISPECSRC = $(APISPECSRC)
	@echo ENVSPECSRC = $(ENVSPECSRC)
	@echo EXTSPECSRC = $(EXTSPECSRC)

# API spec

# Top-level spec source file
APISPEC = OpenCL_API
APISPECSRC = $(APISPEC).txt $(GENDEPENDS) \
    $(shell grep ^include:: $(APISPEC).txt | sed -e 's/^include:://' -e 's/\[\]/ /' | xargs echo)

apihtml: $(HTMLDIR)/$(APISPEC).html $(APISPECSRC)

$(HTMLDIR)/$(APISPEC).html: $(APISPECSRC) katexinst
	$(QUIET)$(ASCIIDOCTOR) -b html5 $(ADOCOPTS) $(ADOCHTMLOPTS) -o $@ $(APISPEC).txt

apipdf: $(PDFDIR)/$(APISPEC).pdf $(APISPECSRC)

$(PDFDIR)/$(APISPEC).pdf: $(APISPECSRC)
	$(QUIET)$(MKDIR) $(PDFDIR)
	$(QUIET)$(MKDIR) $(PDFMATHDIR)
	$(QUIET)$(ASCIIDOCTOR) -b pdf $(ADOCOPTS) $(ADOCPDFOPTS) -o $@ $(APISPEC).txt
ifndef GS_EXISTS
	$(QUIET) echo "Warning: Ghostscript not installed, skipping pdf optimization"
else
	$(QUIET)$(CURDIR)/config/optimize-pdf $@
	$(QUIET)rm $@
	$(QUIET)mv $(PDFDIR)/$(APISPEC)-optimized.pdf $@
endif

# Environment spec

# Top-level spec source file
ENVSPEC = OpenCL_Env
ENVSPECSRC = $(ENVSPEC).txt $(GENDEPENDS) \
    $(shell grep ^include:: $(ENVSPEC).txt | sed -e 's/^include:://' -e 's/\[\]/ /' | xargs echo)

envhtml: $(HTMLDIR)/$(ENVSPEC).html $(ENVSPECSRC)

$(HTMLDIR)/$(ENVSPEC).html: $(ENVSPECSRC) katexinst
	$(QUIET)$(ASCIIDOCTOR) -b html5 $(ADOCOPTS) $(ADOCHTMLOPTS) -o $@ $(ENVSPEC).txt

envpdf: $(PDFDIR)/$(ENVSPEC).pdf $(ENVSPECSRC)

$(PDFDIR)/$(ENVSPEC).pdf: $(ENVSPECSRC)
	$(QUIET)$(MKDIR) $(PDFDIR)
	$(QUIET)$(MKDIR) $(PDFMATHDIR)
	$(QUIET)$(ASCIIDOCTOR) -b pdf $(ADOCOPTS) $(ADOCPDFOPTS) -o $@ $(ENVSPEC).txt
ifndef GS_EXISTS
	$(QUIET) echo "Warning: Ghostscript not installed, skipping pdf optimization"
else
	$(QUIET)$(CURDIR)/config/optimize-pdf $@
	$(QUIET)rm $@
	$(QUIET)mv $(PDFDIR)/$(ENVSPEC)-optimized.pdf $@
endif

# Extensions spec
EXTSPEC = OpenCL_Ext
EXTSPECSRC = $(EXTSPEC).txt $(GENDEPENDS) \
    $(shell grep ^include:: $(EXTSPEC).txt | sed -e 's/^include:://' -e 's/\[\]/ /' | xargs echo)

exthtml: $(HTMLDIR)/$(EXTSPEC).html $(EXTSPECSRC)

$(HTMLDIR)/$(EXTSPEC).html: $(EXTSPECSRC) katexinst
	$(QUIET)$(ASCIIDOCTOR) -b html5 $(ADOCOPTS) $(ADOCHTMLOPTS) -o $@ $(EXTSPEC).txt

extpdf: $(PDFDIR)/$(EXTSPEC).pdf $(EXTSPECSRC)

$(PDFDIR)/$(EXTSPEC).pdf: $(EXTSPECSRC)
	$(QUIET)$(MKDIR) $(PDFDIR)
	$(QUIET)$(MKDIR) $(PDFMATHDIR)
	$(QUIET)$(ASCIIDOCTOR) -b pdf $(ADOCOPTS) $(ADOCPDFOPTS) -o $@ $(EXTSPEC).txt
ifndef GS_EXISTS
	$(QUIET) echo "Warning: Ghostscript not installed, skipping pdf optimization"
else
	$(QUIET)$(CURDIR)/config/optimize-pdf $@
	$(QUIET)rm $@
	$(QUIET)mv $(PDFDIR)/$(EXTSPEC)-optimized.pdf $@
endif

# C++ (cxx) spec
CXXSPEC = OpenCL_Cxx
CXXSPECSRC = $(CXXSPEC).txt $(GENDEPENDS) \
    $(shell grep ^include:: $(CXXSPEC).txt | sed -e 's/^include:://' -e 's/\[\]/ /' | xargs echo)

cxxhtml: $(HTMLDIR)/$(CXXSPEC).html $(CXXSPECSRC)

$(HTMLDIR)/$(CXXSPEC).html: $(CXXSPECSRC) katexinst
	$(QUIET)$(ASCIIDOCTOR) -b html5 $(ADOCOPTS) $(ADOCHTMLOPTS) -o $@ $(CXXSPEC).txt

cxxpdf: $(PDFDIR)/$(CXXSPEC).pdf $(CXXSPECSRC)

$(PDFDIR)/$(CXXSPEC).pdf: $(CXXSPECSRC)
	$(QUIET)$(MKDIR) $(PDFDIR)
	$(QUIET)$(MKDIR) $(PDFMATHDIR)
	$(QUIET)$(ASCIIDOCTOR) -b pdf $(ADOCOPTS) $(ADOCPDFOPTS) -o $@ $(CXXSPEC).txt
ifndef GS_EXISTS
	$(QUIET) echo "Warning: Ghostscript not installed, skipping pdf optimization"
else
	$(QUIET)$(CURDIR)/config/optimize-pdf $@
	$(QUIET)rm $@
	$(QUIET)mv $(PDFDIR)/$(CXXSPEC)-optimized.pdf $@
endif

# C spec
CSPEC = OpenCL_C
CSPECSRC = $(CSPEC).txt $(GENDEPENDS) \
    $(shell grep ^include:: $(CSPEC).txt | sed -e 's/^include:://' -e 's/\[\]/ /' | xargs echo)

chtml: $(HTMLDIR)/$(CSPEC).html $(CSPECSRC)

$(HTMLDIR)/$(CSPEC).html: $(CSPECSRC) katexinst
	$(QUIET)$(ASCIIDOCTOR) -b html5 $(ADOCOPTS) $(ADOCHTMLOPTS) -o $@ $(CSPEC).txt

cpdf: $(PDFDIR)/$(CSPEC).pdf $(CSPECSRC)

$(PDFDIR)/$(CSPEC).pdf: $(CSPECSRC)
	$(QUIET)$(MKDIR) $(PDFDIR)
	$(QUIET)$(MKDIR) $(PDFMATHDIR)
	$(QUIET)$(ASCIIDOCTOR) -b pdf $(ADOCOPTS) $(ADOCPDFOPTS) -o $@ $(CSPEC).txt
ifndef GS_EXISTS
	$(QUIET) echo "Warning: Ghostscript not installed, skipping pdf optimization"
else
	$(QUIET)$(CURDIR)/config/optimize-pdf $@
	$(QUIET)rm $@
	$(QUIET)mv $(PDFDIR)/$(CSPEC)-optimized.pdf $@
endif

# ICD installation guidelines
ICDINSTSPEC = OpenCL_ICD_Installation
ICDINSTSPECSRC = $(ICDINSTSPEC).txt \
    $(shell grep ^include:: $(ICDINSTSPEC).txt | sed -e 's/^include:://' -e 's/\[\]/ /' | xargs echo)

icdinsthtml: $(HTMLDIR)/$(ICDINSTSPEC).html $(ICDINSTSPECSRC)

$(HTMLDIR)/$(ICDINSTSPEC).html: $(ICDINSTSPECSRC) katexinst
	$(QUIET)$(ASCIIDOCTOR) -b html5 $(ADOCOPTS) $(ADOCHTMLOPTS) -o $@ $(ICDINSTSPEC).txt

icdinstpdf: $(PDFDIR)/$(ICDINSTSPEC).pdf $(ICDINSTSPECSRC)

$(PDFDIR)/$(ICDINSTSPEC).pdf: $(ICDINSTSPECSRC)
	$(QUIET)$(MKDIR) $(PDFDIR)
	$(QUIET)$(MKDIR) $(PDFMATHDIR)
	$(QUIET)$(ASCIIDOCTOR) -b pdf $(ADOCOPTS) $(ADOCPDFOPTS) -o $@ $(ICDINSTSPEC).txt
ifndef GS_EXISTS
	$(QUIET) echo "Warning: Ghostscript not installed, skipping pdf optimization"
else
	$(QUIET)$(CURDIR)/config/optimize-pdf $@
	$(QUIET)rm $@
	$(QUIET)mv $(PDFDIR)/$(ICDINSTSPEC)-optimized.pdf $@
endif

# Clean generated and output files

clean: clean_html clean_pdf clean_generated

clean_html:
	$(QUIET)$(RMRF) $(HTMLDIR) $(OUTDIR)/katex

clean_pdf:
	$(QUIET)$(RMRF) $(PDFDIR) $(PDFMATHDIR)

clean_generated:
	$(QUIET)$(RMRF) $(APIINCDIR)/* clapi.py
	$(QUIET)$(RM) man/apispec.txt $(LOGFILE) man/[Cc][Ll]*.txt man/PFN*.txt
	$(QUIET)$(RMRF) $(PDFMATHDIR)

# Ref page targets for individual pages
MANDIR	    := man
MANSECTION  := 3

# These lists should be autogenerated

# Ref page sources for all CL interfaces

MANSOURCES   = $(wildcard $(MANDIR)/[Cc][Ll]*.txt $(MANDIR)/PFN*.txt)
MANCOPYRIGHT = $(MANDIR)/copyright-ccby.txt $(MANDIR)/footer.txt

# Generation of ref page asciidoctor sources by extraction from the
# specification(s).
#
# Should have a proper dependency causing the man page sources to be
# generated by running genRef (once), but adding $(MANSOURCES) to the
# targets causes genRef to run once/target.
#
# Should pass in $(EXTOPTIONS) to determine which pages to generate.
# For now, all core and extension ref pages are extracted by genRef.py.
LOGFILE = man/logfile
## Temporary - eventually should be all spec asciidoctor source files
SPECFILES = api/opencl_platform_layer.txt

man/apispec.txt: $(SPECFILES) genRef.py reflib.py clapi.py
	$(PYTHON) genRef.py -log $(LOGFILE) $(SPECFILES)

# These targets are HTML5 ref pages
#
# The recursive $(MAKE) is an apparently unavoidable hack, since the
# actual list of man page sources isn't known until after
# man/apispec.txt is generated. $(GENDEPENDS) is generated before
# running the recursive make, so it doesn't trigger twice
manhtmlpages: man/apispec.txt $(GENDEPENDS)
	$(MAKE) -e buildmanpages

MANHTMLDIR  = $(OUTDIR)/man/html
MANHTML     = $(MANSOURCES:$(MANDIR)/%.txt=$(MANHTMLDIR)/%.html)
buildmanpages: $(MANHTML)

$(MANHTMLDIR)/%.html: KATEXDIR = ../../katex
$(MANHTMLDIR)/%.html: $(MANDIR)/%.txt $(MANCOPYRIGHT) $(GENDEPENDS) katexinst
	$(QUIET)$(MKDIR) $(MANHTMLDIR)
	$(QUIET)$(ASCIIDOC) -b html5 -a cross-file-links \
	    -a html_spec_relative='../../specs/2.2/html/OpenCL_API.html' \
	    $(ADOCOPTS) $(ADOCHTMLOPTS) -d manpage -o $@ $<

# Targets generated from the XML and registry processing scripts
#   clapi.py - Python encoding of the registry
#   $(APIINCDIR)/timeMarker - proxy for 'apiinc' - generate API interfaces
#
# $(GENSCRIPTEXTRA) are extra options that can be passed to the
# generation script, such as
#   '-diag diag'

REGISTRY   = xml
APIXML	   = $(REGISTRY)/cl.xml
GENSCRIPT  = $(REGISTRY)/gencl.py
GENSCRIPTOPTS  = $(VERSIONOPTIONS) $(EXTOPTIONS) $(GENSCRIPTEXTRA) -registry $(APIXML)
GENSCRIPTEXTRA =

clapi.py: $(APIXML) $(GENSCRIPT)
	$(QUIET)$(PYTHON) $(GENSCRIPT) $(GENSCRIPTOPTS) -o . $@

apiinc: $(APIINCDIR)/timeMarker

$(APIINCDIR)/timeMarker: $(APIXML) $(GENSCRIPT)
	$(QUIET)$(MKDIR) -p $(APIINCDIR)
	$(QUIET)$(PYTHON) $(GENSCRIPT) $(GENSCRIPTOPTS) -o $(APIINCDIR) apiinc

