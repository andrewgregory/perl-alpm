#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include "libalpm/alpm.h"
#include "libalpm/alpm_list.h"
#include "libalpm/deps.h"
#include "libalpm/group.h"
#include "libalpm/sync.h"
#include "libalpm/trans.h"

#include "const-c.inc"

/* These are missing in alpm.h */

/* from deps.h */
/* struct __pmdepend_t {
	pmdepmod_t mod;
	char *name;
	char *version;
}; */

/* from group.h */
/* struct __pmgrp_t { */
	/** group name */
/* 	char *name; */
	/** list of pmpkg_t packages */
/* 	alpm_list_t *packages; */
/* }; */

/* from sync.h */
/* struct __pmsyncpkg_t {
	pmpkgreason_t newreason;
	pmpkg_t *pkg;
	alpm_list_t *removes;
}; */

typedef int           negative_is_error;
typedef pmdb_t      * ALPM_DB;
typedef pmpkg_t     * ALPM_Package;
typedef pmpkg_t     * ALPM_PackageFree;
typedef pmgrp_t     * ALPM_Group;

typedef alpm_list_t * StringListFree;
typedef alpm_list_t * StringListNoFree;
typedef alpm_list_t * PackageListFree;
typedef alpm_list_t * PackageListNoFree;
typedef alpm_list_t * GroupList;
typedef alpm_list_t * DatabaseList;
typedef alpm_list_t * DependList;
typedef alpm_list_t * ListAutoFree;

/* Code references to use as callbacks. */
static SV *cb_log_sub      = NULL;
static SV *cb_download_sub = NULL;
static SV *cb_totaldl_sub  = NULL;

/* String constants to use for log levels (instead of bitflags) */
static const char * log_lvl_error    = "error";
static const char * log_lvl_warning  = "warning";
static const char * log_lvl_debug    = "debug";
static const char * log_lvl_function = "function";
static const char * log_lvl_unknown  = "unknown";

void cb_log_wrapper ( pmloglevel_t level, char * format, va_list args )
{
    SV *s_level, *s_message;
    char *lvl_str;
    int lvl_len;
    dSP;

    if ( cb_log_sub == NULL ) return;

    /* convert log level bitflag to a string */
    switch ( level ) {
    case PM_LOG_ERROR:
        lvl_str = (char *)log_lvl_error;
        break;
    case PM_LOG_WARNING:
        lvl_str = (char *)log_lvl_warning;
        break;
    case PM_LOG_DEBUG:
        lvl_str = (char *)log_lvl_debug;
        break;
    case PM_LOG_FUNCTION:
        lvl_str = (char *)log_lvl_function;
        break;
    default:
        lvl_str = (char *)log_lvl_unknown; 
    }
    lvl_len = strlen( lvl_str );

    ENTER;
    SAVETMPS;

    s_level   = sv_2mortal( newSVpv( lvl_str, lvl_len ) );
    s_message = sv_newmortal();
    sv_vsetpvfn( s_message, format, strlen(format), &args, (SV **)NULL, 0, NULL );
    
    PUSHMARK(SP);
    XPUSHs(s_level);
    XPUSHs(s_message);
    PUTBACK;

    call_sv(cb_log_sub, G_DISCARD);

    FREETMPS;
    LEAVE;
}

void cb_download_wrapper ( const char *filename, off_t xfered, off_t total )
{
    SV *s_filename, *s_xfered, *s_total;
    dSP;

    if ( cb_download_sub == NULL ) return;

    ENTER;
    SAVETMPS;

    s_filename  = sv_2mortal( newSVpv( filename, strlen(filename) ) );
    s_xfered    = sv_2mortal( newSViv( xfered ) );
    s_total     = sv_2mortal( newSViv( total ) );
    
    PUSHMARK(SP);
    XPUSHs(s_filename);
    XPUSHs(s_xfered);
    XPUSHs(s_total);
    PUTBACK;

    call_sv(cb_download_sub, G_DISCARD);

    FREETMPS;
    LEAVE;
}

void cb_totaldl_wrapper ( off_t total )
{
    SV *s_total;
    dSP;

    if ( cb_totaldl_sub == NULL ) return;

    ENTER;
    SAVETMPS;

    s_total = sv_2mortal( newSViv( total ) );
    
    PUSHMARK(SP);
    XPUSHs(s_total);
    PUTBACK;

    call_sv( cb_totaldl_sub, G_DISCARD );

    FREETMPS;
    LEAVE;
}

MODULE = ALPM    PACKAGE = ALPM::ListAutoFree

PROTOTYPES: DISABLE

void
DESTROY(self)
    ListAutoFree self;
  CODE:
#   fprintf( stderr, "DEBUG Freeing memory for ListAutoFree\n" );
    alpm_list_free(self);

MODULE = ALPM    PACKAGE = ALPM::PackageFree

negative_is_error
DESTROY(self)
    ALPM_PackageFree self;
  CODE:
#   fprintf( stderr, "DEBUG Freeing memory for ALPM::PackageFree object\n" );
    RETVAL = alpm_pkg_free(self);
  OUTPUT:
    RETVAL

MODULE = ALPM    PACKAGE = ALPM

INCLUDE: const-xs.inc

ALPM_PackageFree
load_pkgfile(filename, ...)
    const char *filename
  PREINIT:
    pmpkg_t *pkg;
    unsigned short full;
  CODE:
    full = ( items > 1 ? 1 : 0 );
    if ( alpm_pkg_load( filename, full, &pkg ) != 0 )
        croak( "ALPM Error: %s", alpm_strerror( pm_errno ));
    RETVAL = pkg;
  OUTPUT:
    RETVAL

MODULE = ALPM    PACKAGE = ALPM    PREFIX=alpm_

negative_is_error
alpm_initialize()

negative_is_error
alpm_release()

MODULE = ALPM    PACKAGE = ALPM    PREFIX=alpm_option_

SV *
alpm_option_get_logcb()
  CODE:
    RETVAL = ( cb_log_sub == NULL ? &PL_sv_undef : cb_log_sub );
  OUTPUT:
    RETVAL

void
alpm_option_set_logcb(callback)
    SV * callback
  CODE:
    if ( ! SvOK(callback) ) {
        if ( cb_log_sub != NULL ) {
            SvREFCNT_dec( cb_log_sub );
            alpm_option_set_logcb( NULL );
        }
    }
    else {
        if ( ! SvROK(callback) || SvTYPE( SvRV(callback) ) != SVt_PVCV ) {
            croak( "value for logcb option must be a code reference" );
        }

        if ( cb_log_sub != NULL ) SvREFCNT_dec( cb_log_sub );

        cb_log_sub = newSVsv(callback);
        alpm_option_set_logcb( cb_log_wrapper );
    }

#alpm_cb_download alpm_option_get_dlcb();
#void alpm_option_set_dlcb(alpm_cb_download cb);
#
#alpm_cb_totaldl alpm_option_get_totaldlcb();
#void alpm_option_set_totaldlcb(alpm_cb_totaldl cb);

const char *
alpm_option_get_root()

negative_is_error
alpm_option_set_root(root)
    const char * root

const char *
alpm_option_get_dbpath()

negative_is_error
alpm_option_set_dbpath(dbpath)
    const char *dbpath

StringListNoFree
alpm_option_get_cachedirs()

negative_is_error
alpm_option_add_cachedir(cachedir)
    const char * cachedir

void
alpm_option_set_cachedirs(dirlist)
    StringListNoFree dirlist

negative_is_error
alpm_option_remove_cachedir(cachedir)
    const char * cachedir

const char *
alpm_option_get_logfile()

negative_is_error
alpm_option_set_logfile(logfile);
    const char * logfile

const char *
alpm_option_get_lockfile()

unsigned short
alpm_option_get_usesyslog()

void
alpm_option_set_usesyslog(usesyslog)
    unsigned short usesyslog

StringListNoFree
alpm_option_get_noupgrades()

void
alpm_option_add_noupgrade(pkg)
  const char * pkg

void
alpm_option_set_noupgrades(upgrade_list)
    StringListNoFree upgrade_list

negative_is_error
alpm_option_remove_noupgrade(pkg)
    const char * pkg

StringListNoFree
alpm_option_get_noextracts()

void
alpm_option_add_noextract(pkg)
    const char * pkg

void
alpm_option_set_noextracts(noextracts_list)
    StringListNoFree noextracts_list

negative_is_error
alpm_option_remove_noextract(pkg)
    const char * pkg

StringListNoFree
alpm_option_get_ignorepkgs()

void
alpm_option_add_ignorepkg(pkg)
    const char * pkg

void
alpm_option_set_ignorepkgs(ignorepkgs_list)
    StringListNoFree ignorepkgs_list

negative_is_error
alpm_option_remove_ignorepkg(pkg)
    const char * pkg

StringListNoFree
alpm_option_get_holdpkgs()

void
alpm_option_add_holdpkg(pkg)
    const char * pkg

void
alpm_option_set_holdpkgs(holdpkgs_list)
    StringListNoFree holdpkgs_list

negative_is_error
alpm_option_remove_holdpkg(pkg)
    const char * pkg

StringListNoFree
alpm_option_get_ignoregrps()

void
alpm_option_add_ignoregrp(grp)
    const char  * grp

void
alpm_option_set_ignoregrps(ignoregrps_list)
    StringListNoFree ignoregrps_list

negative_is_error
alpm_option_remove_ignoregrp(grp)
    const char  * grp

const char *
alpm_option_get_xfercommand()

void
alpm_option_set_xfercommand(cmd)
    const char * cmd

unsigned short
alpm_option_get_nopassiveftp()

void
alpm_option_set_nopassiveftp(nopasv)
    unsigned short nopasv

void
alpm_option_set_usedelta(usedelta)
    unsigned short usedelta

SV *
alpm_option_get_localdb()
  PREINIT:
    pmdb_t *db;
  CODE:
    db = alpm_option_get_localdb();
    if ( db == NULL )
        RETVAL = &PL_sv_undef;
    else {
        RETVAL = newSV(0);
        sv_setref_pv( RETVAL, "ALPM::DB", (void *)db );
    }
  OUTPUT:
    RETVAL

DatabaseList
alpm_option_get_syncdbs()

MODULE = ALPM    PACKAGE = ALPM    PREFIX=alpm_

ALPM_DB
alpm_db_register_local()

ALPM_DB
alpm_db_register_sync(sync_name)
    const char * sync_name

MODULE = ALPM   PACKAGE = ALPM::DB    PREFIX=alpm_db_

negative_is_error
alpm_db_unregister_all()

const char *
alpm_db_get_name(db)
    ALPM_DB db

const char *
alpm_db__get_url(db)
    ALPM_DB db
  CODE:
    RETVAL = alpm_db_get_url(db);
  OUTPUT:
    RETVAL

negative_is_error
alpm_db__set_server(db, url)
    ALPM_DB db
    const char * url
  CODE:
    RETVAL = alpm_db_setserver(db, url);
  OUTPUT:
    RETVAL

negative_is_error
alpm_db_update(db, level)
    ALPM_DB db
    int level
  CODE:
    RETVAL = alpm_db_update(level, db);
  OUTPUT:
    RETVAL

SV *
alpm_db_get_pkg(db, name)
    ALPM_DB db
    const char *name
  PREINIT:
    pmpkg_t *pkg;
  CODE:
    pkg = alpm_db_get_pkg(db, name);
    if ( pkg == NULL ) RETVAL = &PL_sv_undef;
    else {
        RETVAL = newSV(0);
        sv_setref_pv( RETVAL, "ALPM::Package", (void *)pkg );
    }
  OUTPUT:
    RETVAL

PackageListNoFree
alpm_db_get_pkg_cache(db)
    ALPM_DB db
  CODE:
    RETVAL = alpm_db_getpkgcache(db);
  OUTPUT:
    RETVAL

PackageListNoFree
alpm_db_get_group(db, name)
    ALPM_DB      db
    const char   * name
  PREINIT:
    pmgrp_t *group;
  CODE:
    group = alpm_db_readgrp(db, name);
    RETVAL = ( group == NULL ? NULL : group->packages );
  OUTPUT:
    RETVAL
  
GroupList
alpm_db_get_group_cache(db)
    ALPM_DB       db
  CODE:
    RETVAL = alpm_db_getgrpcache(db);
  OUTPUT:
    RETVAL

PackageListFree
alpm_db_search(db, needles)
    ALPM_DB        db
    StringListFree needles

MODULE=ALPM    PACKAGE=ALPM::Package    PREFIX=alpm_pkg_
    
negative_is_error
alpm_pkg_checkmd5sum(pkg)
    ALPM_Package pkg

# TODO: implement this in perl with LWP
#char *
#alpm_fetch_pkgurl(url)
#    const char *url

int
alpm_pkg_vercmp(a, b)
    const char *a
    const char *b

StringListFree
alpm_pkg_compute_requiredby(pkg)
    ALPM_Package pkg

const char *
alpm_pkg_get_filename(pkg)
    ALPM_Package pkg

const char *
alpm_pkg_get_name(pkg)
    ALPM_Package pkg

const char *
alpm_pkg_get_version(pkg)
    ALPM_Package pkg

const char *
alpm_pkg_get_desc(pkg)
    ALPM_Package pkg

const char *
alpm_pkg_get_url(pkg)
    ALPM_Package pkg

time_t
alpm_pkg_get_builddate(pkg)
    ALPM_Package pkg

time_t
alpm_pkg_get_installdate(pkg)
    ALPM_Package pkg

const char *
alpm_pkg_get_packager(pkg)
    ALPM_Package pkg

const char *
alpm_pkg_get_md5sum(pkg)
    ALPM_Package pkg

const char *
alpm_pkg_get_arch(pkg)
    ALPM_Package pkg

off_t
alpm_pkg_get_size(pkg)
    ALPM_Package pkg

off_t
alpm_pkg_get_isize(pkg)
    ALPM_Package pkg

pmpkgreason_t
alpm_pkg_get_reason(pkg)
    ALPM_Package pkg

StringListNoFree
alpm_pkg_get_licenses(pkg)
    ALPM_Package pkg

StringListNoFree
alpm_pkg_get_groups(pkg)
    ALPM_Package pkg

DependList
alpm_pkg_get_depends(pkg)
    ALPM_Package pkg

StringListNoFree
alpm_pkg_get_optdepends(pkg)
    ALPM_Package pkg

StringListNoFree
alpm_pkg_get_conflicts(pkg)
    ALPM_Package pkg

StringListNoFree
alpm_pkg_get_provides(pkg)
    ALPM_Package pkg

StringListNoFree
alpm_pkg_get_deltas(pkg)
    ALPM_Package pkg

StringListNoFree
alpm_pkg_get_replaces(pkg)
    ALPM_Package pkg

StringListNoFree
alpm_pkg_get_files(pkg)
    ALPM_Package pkg

StringListNoFree
alpm_pkg_get_backup(pkg)
    ALPM_Package pkg

# TODO: create get_changelog() method that does all this at once, easy with perl
# void *alpm_pkg_changelog_open(ALPM_Package pkg);
# size_t alpm_pkg_changelog_read(void *ptr, size_t size,
# 		const ALPM_Package pkg, const void *fp);
# int alpm_pkg_changelog_feof(const ALPM_Package pkg, void *fp);
# int alpm_pkg_changelog_close(const ALPM_Package pkg, void *fp);

unsigned short
alpm_pkg_has_scriptlet(pkg)
    ALPM_Package pkg

unsigned short
alpm_pkg_has_force(pkg)
    ALPM_Package pkg

off_t
alpm_pkg_download_size(newpkg)
    ALPM_Package newpkg

MODULE=ALPM    PACKAGE=ALPM::Group    PREFIX=alpm_grp_

const char *
alpm_grp_get_name(grp)
    ALPM_Group grp

PackageListNoFree
alpm_grp_get_pkgs(grp)
    ALPM_Group grp

MODULE=ALPM    PACKAGE=ALPM

negative_is_error
alpm_trans_init(type, flags)
    int type
    int flags
  CODE:
    RETVAL = alpm_trans_init( type, flags, NULL, NULL, NULL );
  OUTPUT:
    RETVAL

MODULE=ALPM    PACKAGE=ALPM::Transaction

# This is used internally, we keep the full name
negative_is_error
alpm_trans_addtarget(target)
    char * target

negative_is_error
DESTROY(self)
    SV * self
  CODE:
    fprintf( stderr, "DEBUG Releasing the transaction\n" );
    RETVAL = alpm_trans_release();
  OUTPUT:
    RETVAL

MODULE=ALPM    PACKAGE=ALPM::Transaction    PREFIX=alpm_trans_

negative_is_error
alpm_trans_commit(self)
    SV * self
  PREINIT:
    alpm_list_t *errors;
    HV *trans;
    SV **prepared;
  CODE:
    trans = (HV *) SvRV(self);
    prepared = hv_fetch( trans, "prepared", 8, 0 );

    /* prepare before we commit */
    if ( ! SvOK(*prepared) || ! SvTRUE(*prepared) ) {
        PUSHMARK(SP);
        XPUSHs(self);
        PUTBACK;
#        fprintf( stderr, "DEBUG: before call_method\n" );
        call_method( "prepare", G_DISCARD );
#        fprintf( stderr, "DEBUG: after call_method\n" );
    }
    
    errors = NULL;
    RETVAL = alpm_trans_commit( &errors );
  OUTPUT:
    RETVAL

negative_is_error
alpm_trans_interrupt(self)
    SV * self
  CODE:
    RETVAL = alpm_trans_interrupt();
  OUTPUT:
    RETVAL

negative_is_error
alpm_trans_prepare(self)
    SV * self
  PREINIT:
    alpm_list_t *errors;
    HV *trans;
    SV **prepared;
  CODE:
    trans = (HV *) SvRV(self);

    prepared = hv_fetch( trans, "prepared", 8, 0 );
    if ( SvOK(*prepared) && SvTRUE(*prepared) ) {
        RETVAL = 0;
    }   
    else {
        hv_store( trans, "prepared", 8, newSViv(1), 0 );
        #fprintf( stderr, "DEBUG: ALPM::Transaction::prepare\n" );

        errors = NULL;
        RETVAL = alpm_trans_prepare( &errors );
    }
  OUTPUT:
    RETVAL

negative_is_error
alpm_trans_sysupgrade(self)
    SV * self
  CODE:
    RETVAL = alpm_trans_sysupgrade();
  OUTPUT:
    RETVAL

# EOF
