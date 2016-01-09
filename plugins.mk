# Configuration

JOREL_CONFIG ?= jorel.config
JOREL_BUILD ?= false

JOREL_URL ?= https://github.com/emedia-project/jorel/wiki/jorel

ifeq ($(JOREL_BUILD),true)
JOREL ?= $(DEPS_DIR)/jorel/jorel
else
JOREL ?= $(CURDIR)/.jorel/jorel
endif

export JOREL

help::
	$(verbose) printf "%s\n" "" \
		"Jorel targets:" \
		"  jorel.release        Create a release with Jorel" \
		"  jorel.exec cmd=CMD   Execute the Jorel command specified" \
	  "" \
		"Jorel rules accepts the following options :" \
		" * o=OUTPUT_DIR" \
		" * n=REL_NAME" \
		" * v=REL_VERSION" \
		" * c=CONFIG_FILE"

jorel.release: 
	$(verbose) make jorel.exec cmd=release

$(JOREL_CONFIG):
	$(verbose) make jorel.exec cmd=gen_config

ifeq ($(cmd),gen_config)
jorel.exec: jorel.run
else
jorel.exec: $(JOREL_CONFIG) jorel.run
endif

jorel.run: app $(JOREL) 
ifndef cmd
	$(error Usage: $(MAKE) jorel.exec cmd=CMD)
endif
	$(eval x := )
ifdef o
	$(eval x := --output-dir $o $x)
endif
ifdef n
	$(eval x := --relname $n $x)
endif
ifdef v
	$(eval x := --relvsn $v $x)
endif
ifdef c
	$(eval x := --config $c $x)
endif
	$(verbose) $(JOREL) $(cmd) $x

ifeq ($(JOREL_BUILD),true)
$(JOREL): rel-deps
else
$(JOREL):
	$(verbose) mkdir -p $(CURDIR)/.jorel
	$(gen_verbose) $(call core_http_get,$(JOREL),$(JOREL_URL))
	$(verbose) chmod +x $(JOREL)

distclean::
	$(verbose) rm -rf $(CURDIR)/.jorel
endif

