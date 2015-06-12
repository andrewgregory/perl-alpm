#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

#include <alpm.h>
#include "cb.h"
#include "types.h"

SV * logcb_ref, * dlcb_ref, * totaldlcb_ref, * fetchcb_ref;
SV * questioncb_ref, * eventcb_ref, * progresscb_ref;

void c2p_logcb(alpm_loglevel_t lvl, const char * fmt, va_list args)
{
	SV * svlvl, * svmsg;
	const char *str;
	char buf[256];
	dSP;

	if(!logcb_ref) return;

	/* convert log level bitflag to a string */
	switch(lvl){
	case ALPM_LOG_ERROR: str = "error"; break;
	case ALPM_LOG_WARNING: str = "warning"; break;
	case ALPM_LOG_DEBUG: str = "debug"; break;
	case ALPM_LOG_FUNCTION: str = "function"; break;
	default: str = "unknown"; break;
	}

	ENTER;
	SAVETMPS;

	/* We can't use sv_vsetpvfn because it doesn't like j's: %jd or %ji, etc... */
	svlvl = sv_2mortal(newSVpv(str, 0));
	vsnprintf(buf, 255, fmt, args);
	svmsg = sv_2mortal(newSVpv(buf, 0));
	
	PUSHMARK(SP);
	XPUSHs(svlvl);
	XPUSHs(svmsg);
	PUTBACK;

	call_sv(logcb_ref, G_DISCARD);

	FREETMPS;
	LEAVE;
	return;
}

void
c2p_dlcb(const char * name, off_t curr, off_t total)
{
	SV * svname, * svcurr, * svtotal;
	dSP;

	if(!dlcb_ref){
		return;
	}

	ENTER;
	SAVETMPS;
	svname = sv_2mortal(newSVpv(name, 0));
	svcurr = sv_2mortal(newSViv(curr));
	svtotal = sv_2mortal(newSViv(total));

	PUSHMARK(SP);
	XPUSHs(svname);
	XPUSHs(svcurr);
	XPUSHs(svtotal);
	PUTBACK;
	call_sv(dlcb_ref, G_DISCARD);

	FREETMPS;
	LEAVE;
	return;
}

int
c2p_fetchcb(const char * url, const char * dest, int force)
{
	SV * svret;
	int ret;
	dSP;

	if(!fetchcb_ref){
		return -1;
	}

	ENTER;
	SAVETMPS;

	PUSHMARK(SP);
	EXTEND(SP, 3);
	PUSHs(sv_2mortal(newSVpv(url, 0)));
	PUSHs(sv_2mortal(newSVpv(dest, 0)));
	PUSHs(sv_2mortal(newSViv(force)));
	PUTBACK;

	ret = 0;
	if(call_sv(fetchcb_ref, G_SCALAR | G_EVAL) == 1){
		svret = POPs;
		if(SvTRUE(ERRSV)){
			/* the callback died, return an error to libalpm */
			ret = -1;
		}else{
			ret = (SvTRUE(svret) ? 1 : 0);
		}
	}

	FREETMPS;
	LEAVE;
	return ret;
}

void
c2p_totaldlcb(off_t total)
{
	dSP;
	if(!totaldlcb_ref){
		return;
	}
	ENTER;
	SAVETMPS;

	PUSHMARK(SP);
	EXTEND(SP, 1);
	PUSHs(sv_2mortal(newSViv(total)));
	PUTBACK;
	call_sv(totaldlcb_ref, G_DISCARD);

	FREETMPS;
	LEAVE;
	return;
	
}

static SV *
c2p_delta(alpm_delta_t *d)
{
    HV * dhv = newHV();
    hv_stores(dhv, "delta", newSVpv(d->delta, 0));
    hv_stores(dhv, "delta_md5", newSVpv(d->delta_md5, 0));
    hv_stores(dhv, "from", newSVpv(d->from, 0));
    hv_stores(dhv, "to", newSVpv(d->to, 0));
    hv_stores(dhv, "delta_size", newSViv(d->delta_size));
    hv_stores(dhv, "download_size", newSViv(d->download_size));
    return sv_bless(newRV_noinc((SV*)dhv), gv_stashpv("ALPM::Delta", GV_ADD));
}

static SV *
c2p_event(alpm_event_t *ev)
{
    HV * evhv = newHV();
    char *eclass = "ALPM::Event";
    hv_stores(evhv, "type", newSViv(ev->type));
    switch(ev->type) {
        case ALPM_EVENT_CHECKDEPS_DONE:
            eclass = "ALPM::Event::CheckDependencies::Start";
            break;
        case ALPM_EVENT_CHECKDEPS_START:
            eclass = "ALPM::Event::CheckDependencies::Start";
            break;
        case ALPM_EVENT_DATABASE_MISSING:
            {
                alpm_event_database_missing_t *e = (alpm_event_database_missing_t *)ev;
                eclass = "ALPM::Event::DatabaseMissing";
                hv_stores(evhv, "dbname", newSVpv(e->dbname, 0));
            }
            break;
        case ALPM_EVENT_DELTA_INTEGRITY_DONE:
            eclass = "ALPM::Event::Delta::Integrity::Done";
            break;
        case ALPM_EVENT_DELTA_INTEGRITY_START:
            eclass = "ALPM::Event::Delta::Integrity::Start";
            break;
        case ALPM_EVENT_DELTA_PATCHES_DONE:
            {
                alpm_event_delta_patch_t *e = (alpm_event_delta_patch_t *)ev;
                eclass = "ALPM::Event::Delta::Patches::Done";
                hv_stores(evhv, "delta", c2p_delta(e->delta));
            }
            break;
        case ALPM_EVENT_DELTA_PATCHES_START:
            {
                alpm_event_delta_patch_t *e = (alpm_event_delta_patch_t *)ev;
                eclass = "ALPM::Event::Delta::Patches::Start";
                hv_stores(evhv, "delta", c2p_delta(e->delta));
            }
            break;
        case ALPM_EVENT_DELTA_PATCH_DONE:
            {
                alpm_event_delta_patch_t *e = (alpm_event_delta_patch_t *)ev;
                eclass = "ALPM::Event::Delta::Patch::Done";
                hv_stores(evhv, "delta", c2p_delta(e->delta));
            }
            break;
        case ALPM_EVENT_DELTA_PATCH_FAILED:
            {
                alpm_event_delta_patch_t *e = (alpm_event_delta_patch_t *)ev;
                eclass = "ALPM::Event::Delta::Patch::Failed";
                hv_stores(evhv, "delta", c2p_delta(e->delta));
            }
            break;
        case ALPM_EVENT_DELTA_PATCH_START:
            {
                alpm_event_delta_patch_t *e = (alpm_event_delta_patch_t *)ev;
                eclass = "ALPM::Event::Delta::Patch::Start";
                hv_stores(evhv, "delta", c2p_delta(e->delta));
            }
            break;
        case ALPM_EVENT_DISKSPACE_DONE:
            eclass = "ALPM::Event::Diskspace::Done";
            break;
        case ALPM_EVENT_DISKSPACE_START:
            eclass = "ALPM::Event::Diskspace::Start";
            break;
        case ALPM_EVENT_FILECONFLICTS_DONE:
            eclass = "ALPM::Event::FileConflicts::Done";
            break;
        case ALPM_EVENT_FILECONFLICTS_START:
            eclass = "ALPM::Event::FileConflicts::Start";
            break;
        case ALPM_EVENT_INTEGRITY_DONE:
            eclass = "ALPM::Event::Integrity::Done";
            break;
        case ALPM_EVENT_INTEGRITY_START:
            eclass = "ALPM::Event::Integrity::Start";
            break;
        case ALPM_EVENT_INTERCONFLICTS_DONE:
            eclass = "ALPM::Event::InterConflicts::Done";
            break;
        case ALPM_EVENT_INTERCONFLICTS_START:
            eclass = "ALPM::Event::InterConflicts::Start";
            break;
        case ALPM_EVENT_KEYRING_DONE:
            eclass = "ALPM::Event::Keyring::Done";
            break;
        case ALPM_EVENT_KEYRING_START:
            eclass = "ALPM::Event::Keyring::Start";
            break;
        case ALPM_EVENT_KEY_DOWNLOAD_DONE:
            eclass = "ALPM::Event::Key::Download::Done";
            break;
        case ALPM_EVENT_KEY_DOWNLOAD_START:
            eclass = "ALPM::Event::Key::Download::Start";
            break;
        case ALPM_EVENT_LOAD_DONE:
            eclass = "ALPM::Event::Load::Done";
            break;
        case ALPM_EVENT_LOAD_START:
            eclass = "ALPM::Event::Load::Start";
            break;
        case ALPM_EVENT_OPTDEP_REMOVAL:
            {
                alpm_event_optdep_removal_t *e = (alpm_event_optdep_removal_t *)ev;
                eclass = "ALPM::Event::OptionalDependency::Removal";
                hv_stores(evhv, "package", c2p_pkg(e->pkg));
                hv_stores(evhv, "optdep", c2p_pkg(e->optdep));
            }
            break;
        case ALPM_EVENT_PACKAGE_OPERATION_DONE:
            {
                alpm_event_package_operation_t *e = (alpm_event_package_operation_t*) ev;
                switch(e->operation) {
                    case ALPM_PACKAGE_INSTALL: eclass = "ALPM::Event::Package::Install::Done"; break;
                    case ALPM_PACKAGE_UPGRADE: eclass = "ALPM::Event::Package::Upgrade::Done"; break;
                    case ALPM_PACKAGE_REINSTALL: eclass = "ALPM::Event::Package::Reinstall::Done"; break;
                    case ALPM_PACKAGE_DOWNGRADE: eclass = "ALPM::Event::Package::Downgrade::Done"; break;
                    case ALPM_PACKAGE_REMOVE: eclass = "ALPM::Event::Package::Remove::Done"; break;
                    default: eclass = "ALPM::Event::Package::Operation::Done"; break;
                }
                hv_stores(evhv, "oldpkg", c2p_pkg(e->oldpkg));
                hv_stores(evhv, "newpkg", c2p_pkg(e->newpkg));
            }
            break;
        case ALPM_EVENT_PACKAGE_OPERATION_START:
            {
                alpm_event_package_operation_t *e = (alpm_event_package_operation_t*) ev;
                switch(e->operation) {
                    case ALPM_PACKAGE_INSTALL: eclass = "ALPM::Event::Package::Install::Start"; break;
                    case ALPM_PACKAGE_UPGRADE: eclass = "ALPM::Event::Package::Upgrade::Start"; break;
                    case ALPM_PACKAGE_REINSTALL: eclass = "ALPM::Event::Package::Reinstall::Start"; break;
                    case ALPM_PACKAGE_DOWNGRADE: eclass = "ALPM::Event::Package::Downgrade::Start"; break;
                    case ALPM_PACKAGE_REMOVE: eclass = "ALPM::Event::Package::Remove::Start"; break;
                    default: eclass = "ALPM::Event::Package::Operation::Start"; break;
                }
                hv_stores(evhv, "oldpkg", c2p_pkg(e->oldpkg));
                hv_stores(evhv, "newpkg", c2p_pkg(e->newpkg));
            }
            break;
        case ALPM_EVENT_PACNEW_CREATED:
            {
                alpm_event_pacnew_created_t *e = (alpm_event_pacnew_created_t*) ev;
                eclass = "ALPM::Event::PacnewCreated";
                hv_stores(evhv, "from_noupgrade", newSViv(e->from_noupgrade));
                hv_stores(evhv, "oldpkg", c2p_pkg(e->oldpkg));
                hv_stores(evhv, "newpkg", c2p_pkg(e->newpkg));
                hv_stores(evhv, "file", newSVpv(e->file, 0));
            }
            break;
        case ALPM_EVENT_PACSAVE_CREATED:
            {
                alpm_event_pacsave_created_t *e = (alpm_event_pacsave_created_t*) ev;
                eclass = "ALPM::Event::PacsaveCreated";
                hv_stores(evhv, "newpkg", c2p_pkg(e->oldpkg));
                hv_stores(evhv, "file", newSVpv(e->file, 0));
            }
            break;
        case ALPM_EVENT_PKGDOWNLOAD_DONE:
            {
                alpm_event_pkgdownload_t *e = (alpm_event_pkgdownload_t*) ev;
                eclass = "ALPM::Event::Package::Download::Done";
                hv_stores(evhv, "file", newSVpv(e->file, 0));
            }
            break;
        case ALPM_EVENT_PKGDOWNLOAD_FAILED:
            {
                alpm_event_pkgdownload_t *e = (alpm_event_pkgdownload_t*) ev;
                eclass = "ALPM::Event::Package::Download::Failed";
                hv_stores(evhv, "file", newSVpv(e->file, 0));
            }
            break;
        case ALPM_EVENT_PKGDOWNLOAD_START:
            {
                alpm_event_pkgdownload_t *e = (alpm_event_pkgdownload_t*)ev;
                eclass = "ALPM::Event::Package::Download::Start";
                hv_stores(evhv, "file", newSVpv(e->file, 0));
            }
            break;
        case ALPM_EVENT_RESOLVEDEPS_DONE:
            eclass = "ALPM::Event::ResolveDependencies::Done";
            break;
        case ALPM_EVENT_RESOLVEDEPS_START:
            eclass = "ALPM::Event::ResolveDependencies::Start";
            break;
        case ALPM_EVENT_RETRIEVE_DONE:
            eclass = "ALPM::Event::Retrieve::Done";
            break;
        case ALPM_EVENT_RETRIEVE_FAILED:
            eclass = "ALPM::Event::Retrieve::Failed";
            break;
        case ALPM_EVENT_RETRIEVE_START:
            eclass = "ALPM::Event::Retrieve::Start";
            break;
        case ALPM_EVENT_SCRIPTLET_INFO:
            {
                alpm_event_scriptlet_info_t *e = (alpm_event_scriptlet_info_t*)ev;
                eclass = "ALPM::Event::Scriptlet::Info";
                hv_stores(evhv, "line", newSVpv(e->line, 0));
            }
            break;
        default:
            eclass = "ALPM::Event";
            warn("unknown event type %d", ev->type);
            break;
    }
    return sv_bless(newRV_noinc((SV*)evhv), gv_stashpv(eclass, GV_ADD));
}

void
c2p_eventcb(alpm_event_t *ev)
{
    SV * svname, * svcurr, * svtotal;
    dSP;

    if(!eventcb_ref){
        return;
    }

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    mXPUSHs(c2p_event(ev));
    PUTBACK;
    call_sv(eventcb_ref, G_DISCARD);

    FREETMPS;
    LEAVE;
    return;
}
