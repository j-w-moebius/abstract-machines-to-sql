# Module big enables the use of multiple source files
MODULE_big = pg_hashtable
EXTENSION = pg_hashtable
DATA = pg_hashtable--1.0.sql

#OBJS = $(patsubst %.c,%.o,$(wildcard *.c))
OBJS = pg_hashtable.o
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

ifeq ($(PORTNAME), darwin)
override CFLAGS += -undefined dynamic_lookup -g
endif

#override CFLAGS += -I$(top_builddir)/src/pl/plpgsql/src