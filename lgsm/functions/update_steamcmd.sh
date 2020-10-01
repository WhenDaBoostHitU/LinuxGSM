#!/bin/bash
# LinuxGSM update_steamcmd.sh function
# Author: Daniel Gibbs
# Website: https://linuxgsm.com
# Description: Handles updating using SteamCMD.

functionselfname="$(basename "$(readlink -f "${BASH_SOURCE[0]}")")"

fn_update_steamcmd_localbuild(){
	# Gets local build info.
	fn_print_dots "Checking local build: ${remotelocation}"
	fn_appmanifest_check
	# Uses appmanifest to find local build.
	localbuild=$(grep buildid "${appmanifestfile}" | tr '[:blank:]"' ' ' | tr -s ' ' | cut -d\  -f3)

	# Set branch to public if no custom branch.
	if [ -z "${branch}" ]; then
		branch="public"
	fi

	# Checks if localbuild variable has been set.
	if [ -z "${localbuild}" ]||[ "${localbuild}" == "null" ]; then
		fn_print_fail "Checking local build: ${remotelocation}"
		fn_script_log_fatal "Checking local build"

		core_exit.sh
	else
		fn_print_ok "Checking local build: ${remotelocation}"
		fn_script_log_pass "Checking local build"
	fi
}

fn_update_steamcmd_remotebuild(){
	# Gets remote build info.
	if [ -d "${steamcmddir}" ]; then
		cd "${steamcmddir}" || exit
	fi

	# Removes appinfo.vdf as a fix for not always getting up to date version info from SteamCMD.
	if [ "$(find "${HOME}" -type f -name "appinfo.vdf" | wc -l)" -ne "0" ]; then
		find "${HOME}" -type f -name "appinfo.vdf" -exec rm -f {} \;
	fi

	if [ -n "${branch}" ]&&[ -n "${betapassword}" ]; then
		remotebuild=$(${steamcmdcommand} +login "${steamuser}" "${steampass}" +app_info_update 1 +app_info_print "${appid}" -beta "${branch}" -betapassword "${betapassword}" +quit | sed '1,/branches/d' | sed "1,/${branch}/d" | grep -m 1 buildid | tr -cd '[:digit:]')
	elif [ -n "${branch}" ]; then
		remotebuild=$(${steamcmdcommand} +login "${steamuser}" "${steampass}" +app_info_update 1 +app_info_print "${appid}" -beta "${branch}" +quit | sed '1,/branches/d' | sed "1,/${branch}/d" | grep -m 1 buildid | tr -cd '[:digit:]')
	else
		remotebuild=$(${steamcmdcommand} +login "${steamuser}" "${steampass}" +app_info_update 1 +app_info_print "${appid}" +quit | sed '1,/branches/d' | sed "1,/${branch}/d" | grep -m 1 buildid | tr -cd '[:digit:]')
	fi

	if [ "${firstcommandname}" != "INSTALL" ]; then
		fn_print_dots "Checking remote build: ${remotelocation}"
		# Checks if remotebuild variable has been set.
		if [ -z "${remotebuild}" ]||[ "${remotebuild}" == "null" ]; then
			fn_print_fail "Checking remote build: ${remotelocation}"
			fn_script_log_fatal "Checking remote build"
			fn_restore_server_state
			core_exit.sh
		else
			fn_print_ok "Checking remote build: ${remotelocation}"
			fn_script_log_pass "Checking remote build"
		fi
	else
		# Checks if remotebuild variable has been set.
		if [ -z "${remotebuild}" ]||[ "${remotebuild}" == "null" ]; then
			fn_print_failure "Unable to get remote build"
			fn_script_log_fatal "Unable to get remote build"
			fn_restore_server_state
			core_exit.sh
		fi
	fi
}

fn_restore_server_state(){
	if [ "${serverstatusbeforewipe}" == "1" ]; then
		command_start.sh
	fi
}

fn_check_force_wipe_date(){

	currentweekday=$(LC_TIME=C date +%A)
	dayofmonth=$(date +%d)

	if [ "${currentweekday}" = "Thursday" ] && [ "${dayofmonth}" -lt "8" ]; then
		forcewipeday=1
	fi
}

fn_check_wipe_date(){
	if [ -n "$(find "${serveridentitydir}" -type f -name "proceduralmap*.map")" ]; then
		# currentdate=$(date +%m%d%Y)
		# mapcreatedate=$(date -r "$(find "${serveridentitydir}" -type f -name "proceduralmap*.map")")
		# mapwipedate=$(date +%m%d%Y -d "${mapcreatedate} + ${wipedays} day")
		# mapcreatedate=$(date +%m%d%Y -d "${mapcreatedate}")

		currentdatetime=$(date +%s)
		timezone=$(date +%Z)

		if [ -f "${lockdir}/${selfname}-lastmapwipe.lock" ]; then
			lastmapwipe=$(cat "${lockdir}/${selfname}-lastmapwipe.lock")
			mapwipedate=$(date +%F -d "${lastmapwipe} + ${wipedays} day")
			mapwipedatetime=$(date +%s -d "${mapwipedate} ${timetowipe} ${timezone}")

			# Wipe if it's a forced wipe day or actual wipe day
			if [ "${currentdatetime}" -ge "${mapwipedatetime}" ] && [ "${forcewipeday}" != "1" ]  ||  ([ "${forcewipeday}" == "1" ] && [ "${forcewipeupdated}" == "1" ]); then
					autowipe=1
					if [ "${forcewipeupdated}" ]; then
						unset forcewipeupdated
					fi
			fi
		fi

		# Only wipe BP's if it's wipe day
		if [ -f "${lockdir}/${selfname}-lastbpwipe.lock" ] && [ "${autowipe}" == "1" ]; then
			lastbpwipe=$(cat "${lockdir}/${selfname}-lastbpwipe.lock")
			bpwipedate=$(date +%F -d "${lastbpwipe} + ${bpwipedays} day")
			bpwipedatetime=$(date +%s -d "${bpwipedate} ${timetowipe} ${timezone}")

			if [ "${currentdatetime}" -ge "${bpwipedatetime}" ]; then
				bpwipe=1
			fi
		fi

		if [ "${autowipe}" == "1" ]; then
			check_status.sh
			serverstatusbeforewipe=${status}
			fn_autowipe_map
		fi
	fi
}

fn_autowipe_map(){
	if [ "${autowipe}" == "1" ]; then
		exitbypass=1
		command_backup.sh
		if [ "${bpwipe}" == "1" ]; then
			wipeall=1
			exitbypass=1
			command_wipe.sh
		else
			exitbypass=1
			command_wipe.sh
		fi
	fi
}

fn_update_steamcmd_compare(){
	fn_print_dots "Checking for update: ${remotelocation}"
	if [ "${localbuild}" != "${remotebuild}" ]; then
		fn_print_ok_nl "Checking for update: ${remotelocation}"
		echo -en "\n"
		echo -e "Update available"
		echo -e "* Local build: ${red}${localbuild}${default}"
		echo -e "* Remote build: ${green}${remotebuild}${default}"
		if [ -n "${branch}" ]; then
			echo -e "* Branch: ${branch}"
		fi
		if [ -n "${betapassword}" ]; then
			echo -e "* Branch password: ${betapassword}"
		fi
		echo -e "https://steamdb.info/app/${appid}/"
		echo -en "\n"
		fn_script_log_info "Update available"
		fn_script_log_info "Local build: ${localbuild}"
		fn_script_log_info "Remote build: ${remotebuild}"
		if [ -n "${branch}" ]; then
			fn_script_log_info "Branch: ${branch}"
		fi
		if [ -n "${betapassword}" ]; then
			fn_script_log_info "Branch password: ${betapassword}"
		fi
		fn_script_log_info "${localbuild} > ${remotebuild}"

		unset updateonstart
		check_status.sh
		# Check if it's force wipe day
		fn_check_force_wipe_date
		# If server stopped.
		if [ "${status}" == "0" ]; then
			if [ "${forcewipeday}" == "1" ]; then
				forcewipeupdated=1
				fn_check_wipe_date
			fi
			exitbypass=1
			fn_dl_steamcmd
			exitbypass=1
			command_mods_update.sh
		# If server started.
		else
			fn_print_restart_warning
			exitbypass=1
			command_stop.sh
			fn_firstcommand_reset
			exitbypass=1
			fn_dl_steamcmd
			exitbypass=1
			command_mods_update.sh
			if [ "${forcewipeday}" == "1" ]; then
				forcewipeupdated=1
				fn_check_wipe_date
			fi			
			exitbypass=1
			command_start.sh
			fn_firstcommand_reset
		fi
		date +%s > "${lockdir}/lastupdate.lock"
		alert="update"
		alert.sh
	else
		# fn_check_force_wipe_date		
		# if [ ${forcewipeday} == "1" ]; then
		# 	fn_check_wipe_date
		# fi
		fn_print_ok_nl "Checking for update: ${remotelocation}"
		echo -en "\n"
		echo -e "No update available"
		echo -e "* Local build: ${green}${localbuild}${default}"
		echo -e "* Remote build: ${green}${remotebuild}${default}"
		if [ -n "${branch}" ]; then
			echo -e "* Branch: ${branch}"
		fi
		if [ -n "${betapassword}" ]; then
			echo -e "* Branch password: ${betapassword}"
		fi
		echo -e "https://steamdb.info/app/${appid}/"
		echo -en "\n"
		fn_script_log_info "No update available"
		fn_script_log_info "Local build: ${localbuild}"
		fn_script_log_info "Remote build: ${remotebuild}"
		if [ -n "${branch}" ]; then
			fn_script_log_info "Branch: ${branch}"
		fi
		if [ -n "${betapassword}" ]; then
			fn_script_log_info "Branch password: ${betapassword}"
		fi
	fi
}

fn_appmanifest_info(){
	appmanifestfile=$(find "${serverfiles}" -type f -name "appmanifest_${appid}.acf")
	appmanifestfilewc=$(find "${serverfiles}" -type f -name "appmanifest_${appid}.acf" | wc -l)
}

fn_appmanifest_check(){
	fn_appmanifest_info
	# Multiple or no matching appmanifest files may sometimes be present.
	# This error is corrected if required.
	if [ "${appmanifestfilewc}" -ge "2" ]; then
		fn_print_error "Multiple appmanifest_${appid}.acf files found"
		fn_script_log_error "Multiple appmanifest_${appid}.acf files found"
		fn_print_dots "Removing x${appmanifestfilewc} appmanifest_${appid}.acf files"
		for appfile in ${appmanifestfile}; do
			rm -f "${appfile:?}"
		done
		appmanifestfilewc1="${appmanifestfilewc}"
		fn_appmanifest_info
		# if error can not be resolved.
		if [ "${appmanifestfilewc}" -ge "2" ]; then
			fn_print_fail "Unable to remove x${appmanifestfilewc} appmanifest_${appid}.acf files"
			fn_script_log_fatal "Unable to remove x${appmanifestfilewc} appmanifest_${appid}.acf files"
			echo -e "* Check user permissions"
			for appfile in ${appmanifestfile}; do
				echo -e "	${appfile}"
			done
			core_exit.sh
		else
			fn_print_ok "Removed x${appmanifestfilewc1} appmanifest_${appid}.acf files"
			fn_script_log_pass "Removed x${appmanifestfilewc1} appmanifest_${appid}.acf files"
			fn_print_info_nl "Forcing update to correct issue"
			fn_script_log_info "Forcing update to correct issue"
			fn_dl_steamcmd
		fi
	elif [ "${appmanifestfilewc}" -eq "0" ]; then
		fn_print_error_nl "No appmanifest_${appid}.acf found"
		fn_script_log_error "No appmanifest_${appid}.acf found"
		fn_print_info_nl "Forcing update to correct issue"
		fn_script_log_info "Forcing update to correct issue"
		fn_dl_steamcmd
		fn_appmanifest_info
		if [ "${appmanifestfilewc}" -eq "0" ]; then
			fn_print_fail_nl "Still no appmanifest_${appid}.acf found"
			fn_script_log_fatal "Still no appmanifest_${appid}.acf found"
			core_exit.sh
		fi
	fi
}

# The location where the builds are checked and downloaded.
remotelocation="SteamCMD"
check.sh

fn_print_dots "${remotelocation}"

if [ "${forceupdate}" == "1" ]; then
	# forceupdate bypasses update checks.
	if [ "${status}" != "0" ]; then
		fn_print_restart_warning
		exitbypass=1
		command_stop.sh
		fn_firstcommand_reset
		fn_dl_steamcmd
		date +%s > "${lockdir}/lastupdate.lock"
		exitbypass=1
		command_start.sh
		fn_firstcommand_reset
	else
		fn_dl_steamcmd
		date +%s > "${lockdir}/lastupdate.lock"
	fi
else
	fn_check_force_wipe_date
	fn_check_wipe_date	
	# fn_print_dots "Checking for update"
	# fn_print_dots "Checking for update: ${remotelocation}"
	fn_update_steamcmd_localbuild
	fn_update_steamcmd_remotebuild
	fn_update_steamcmd_compare
	fn_restore_server_state
fi
