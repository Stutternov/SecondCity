// Microstamping category
/datum/detective_scan_category/microstamp
	id = DETSCAN_CATEGORY_MICROSTAMP
	name = "Microstamping"
	display_order = 10
	ui_icon = "ss-casing"
	ui_icon_color = "yellow"

// Bullet shrapnel category
/datum/detective_scan_category/bullet
	id = DETSCAN_CATEGORY_BULLET
	name = "Bullet shrapnel"
	display_order = 11
	ui_icon = "flask"
	ui_icon_color = "red"

// Unique subtype of the base TG Station scanner.
// Seperated for unique actions in forensics gathering.
/obj/item/darkpack/detective_scanner
	name = "forensics kit"
	desc = "A kit used to detect and gather evidence; particularly that of biomass for DNA, recovery of fingerprints, or closer examination of bullet casings. Can be used to print reports of your findings."
	icon = 'modular_darkpack/modules/deprecated/icons/items.dmi'
	icon_state = "magnifier"
	w_class = WEIGHT_CLASS_SMALL
	inhand_icon_state = "electronic"
	worn_icon_state = "electronic"
	lefthand_file = 'icons/mob/inhands/items/devices_lefthand.dmi'
	righthand_file = 'icons/mob/inhands/items/devices_righthand.dmi'
	item_flags = NOBLUDGEON
	slot_flags = ITEM_SLOT_BELT
	/// if the scanner is currently busy processing
	var/scanner_busy = FALSE
	var/list/log_data = list()
	var/range = 1
	var/view_check = TRUE
	var/forensicPrintCount = 0

/obj/item/darkpack/detective_scanner/interact(mob/user)
	. = ..()
	if(user.stat != CONSCIOUS || !user.can_read(src) || user.is_blind())
		return ITEM_INTERACT_BLOCKING
	ui_interact(user)
	return ITEM_INTERACT_SUCCESS

/**
 * safe_print_report - a wrapper proc for print_report
 *
 * Calls print_report(), and should a runtime occur within we can still reset the 'busy' state
 */
/obj/item/darkpack/detective_scanner/proc/safe_print_report()
	print_report()
	scanner_busy = FALSE

/obj/item/darkpack/detective_scanner/proc/print_report()
	// Create our paper
	var/obj/item/paper/report_paper = new(get_turf(src))

	//This could be a global count like sec and med record printouts. See GLOB.manifest.generalPrintCount AKA datacore.dm
	var/frNum = ++forensicPrintCount

	report_paper.name = "FR-[frNum] 'Forensic Record'"
	var/list/report_text = list("<h1>Forensic Record - (FR-[frNum])</h1><hr>")

	for(var/datum/detective_scanner_log/log_entry as anything in log_data)
		report_text += log_entry.generate_report_text()

	report_text += "<h1>Notes:</h1><br>"

	report_paper.add_raw_text(report_text.Join())
	report_paper.update_appearance()

	if(ismob(loc))
		var/mob/printer = loc
		printer.put_in_hands(report_paper)
		balloon_alert(printer, "logs cleared")

	// Clear the logs
	log_data = list()

/obj/item/darkpack/detective_scanner/interact_with_atom(atom/interacting_with, mob/living/user, list/modifiers)
	if(SHOULD_SKIP_INTERACTION(interacting_with, src, user))
		return NONE // lets us put our scanner away without trying to scan the bag
	safe_scan(user, interacting_with)
	return ITEM_INTERACT_SUCCESS

/obj/item/darkpack/detective_scanner/ranged_interact_with_atom(atom/interacting_with, mob/living/user, list/modifiers)
	safe_scan(user, interacting_with)
	return ITEM_INTERACT_SUCCESS

/**
 * safe_scan - a wrapper proc for scan()
 *
 * calls scan(), and should a runtime occur within we can still reset the 'busy' state
 */
/obj/item/darkpack/detective_scanner/proc/safe_scan(mob/user, atom/atom_to_scan)
	set waitfor = FALSE
	if(scanner_busy)
		balloon_alert(user, "scanner busy!")
		return
	if(!scan(user, atom_to_scan)) // this should only return FALSE if a runtime occurs during the scan proc, so ideally never
		balloon_alert(user, "scanner error!") // but in case it does, we 'error' instead of just bricking the scanner
	scanner_busy = FALSE


/obj/item/darkpack/detective_scanner/proc/scan(mob/user, atom/scanned_atom)
	if(loc != user)
		return TRUE
	// Can scan items we hold and store
	if(!(scanned_atom in user.get_all_contents()))
		// Can remotely scan objects and mobs.
		if((get_dist(scanned_atom, user) > range) || (!(scanned_atom in view(range, user)) && view_check))
			return TRUE
	playsound(src, SFX_INDUSTRIAL_SCAN, 20, TRUE, -2, TRUE, FALSE)
	scanner_busy = TRUE


	user.visible_message(
		span_notice("\The [user] points \the [src] at \the [scanned_atom] and performs a forensic scan."),
		ignored_mobs = user
	)
	to_chat(user, span_notice("You scan \the [scanned_atom]. The scanner is now analysing the results..."))


	// GATHER INFORMATION

	var/datum/detective_scanner_log/log_entry = new

	// Start gathering

	log_entry.scan_target = scanned_atom.name
	log_entry.scan_time = station_time_timestamp()

	var/list/atom_fibers = GET_ATOM_FIBRES(scanned_atom)
	if(length(atom_fibers))
		log_entry.add_data_entry(DETSCAN_CATEGORY_FIBER, atom_fibers.Copy())

	var/list/blood = GET_ATOM_BLOOD_DNA(scanned_atom)
	if(length(blood))
		log_entry.add_data_entry(DETSCAN_CATEGORY_BLOOD, blood.Copy())

	// Skill-check for scans
	var/mob/living/carbon/human/H = user
	var/investigation_dice = H.st_get_stat(STAT_PERCEPTION) + H.st_get_stat(STAT_INVESTIGATION)

	if(ishuman(scanned_atom))
		var/mob/living/carbon/human/scanned_human = scanned_atom
		var/investigation_roll = SSroll.storyteller_roll(investigation_dice, 3, H, src, TRUE)
		if(!investigation_roll > 0)
			log_entry.add_data_entry(DETSCAN_CATEGORY_FINGERS, list("Improper fingerprints; try again."))
		else
			if(!scanned_human.gloves)
				log_entry.add_data_entry(
					DETSCAN_CATEGORY_FINGERS,
					rustg_hash_string(RUSTG_HASH_MD5, scanned_human.dna?.unique_identity)
				)

	else if(!ismob(scanned_atom))
		var/list/atom_fingerprints = GET_ATOM_FINGERPRINTS(scanned_atom)
		var/investigation_roll = SSroll.storyteller_roll(investigation_dice, 5, H, src, TRUE)
		if(!investigation_roll > 0)
			log_entry.add_data_entry(DETSCAN_CATEGORY_FINGERS, list("Improper gathering; try again."))
		else
			if(length(atom_fingerprints))
				log_entry.add_data_entry(DETSCAN_CATEGORY_FINGERS, atom_fingerprints.Copy())

			// Only get reagents from non-mobs.
			for(var/datum/reagent/present_reagent as anything in scanned_atom.reagents?.reagent_list)
				log_entry.add_data_entry(DETSCAN_CATEGORY_REAGENTS, list(present_reagent.name = present_reagent.volume))

				// Get blood data from the blood reagent.
				if(!istype(present_reagent, /datum/reagent/blood))
					continue

				var/blood_DNA = present_reagent.data["blood_DNA"]
				var/blood_type = present_reagent.data["blood_type"]
				if(!blood_DNA || !blood_type)
					continue

				log_entry.add_data_entry(DETSCAN_CATEGORY_BLOOD, list(blood_DNA = blood_type))

	if(istype(scanned_atom, /obj/item/ammo_casing))
		var/investigation_roll = SSroll.storyteller_roll(investigation_dice, 7, H, src, TRUE)
		var/obj/item/ammo_casing/casing = scanned_atom
		if(!investigation_roll > 0)
			log_entry.add_data_entry(DETSCAN_CATEGORY_MICROSTAMP, list("[casing.name] has an incomplete microstamp; you can't make it out."))
		else
			if(casing.serial_type_index)
				log_entry.add_data_entry(DETSCAN_CATEGORY_MICROSTAMP, list("[casing.name] has the serial number [casing.serial_type_index]"))
			else
				log_entry.add_data_entry(DETSCAN_CATEGORY_MICROSTAMP, list("[casing.name] has an incomplete microstamp; you can't make it out."))

	if(istype(scanned_atom, /obj/item/card/id))
		var/obj/item/card/id/user_id = scanned_atom
		var/investigation_roll = SSroll.storyteller_roll(investigation_dice, 3, H, src, TRUE)
		if(!investigation_roll > 0)
			log_entry.add_data_entry(DETSCAN_CATEGORY_ACCESS, list("Improper gathering; try again."))
		else
			for(var/region in DETSCAN_ACCESS_ORDER())
				var/access_in_region = SSid_access.accesses_by_region[region] & user_id.GetAccess()
				if(!length(access_in_region))
					continue
				var/list/access_names = list()
				for(var/access_num in access_in_region)
					access_names += SSid_access.get_access_desc(access_num)

				log_entry.add_data_entry(DETSCAN_CATEGORY_ACCESS, list("[region]" = english_list(access_names)))

	// sends it off to be modified by the items
	SEND_SIGNAL(scanned_atom, COMSIG_DETECTIVE_SCANNED, user, log_entry)

	// Perform sorting now, because probably this will be never modified
	log_entry.sort_data_entries()

	stoplag(3 SECONDS)
	log_data += log_entry
	return TRUE


/obj/item/darkpack/detective_scanner/click_alt(mob/living/user)
	return clear_logs()

/obj/item/darkpack/detective_scanner/examine(mob/user)
	. = ..()
	if(length(log_data) && !scanner_busy)
		. += span_notice("Alt-click to clear scanner logs.")


/obj/item/darkpack/detective_scanner/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "ForensicScanner", "Forensic Scanner")
		ui.open()

/obj/item/darkpack/detective_scanner/ui_data(mob/user)
	var/list/logs = list()
	for(var/datum/detective_scanner_log/log as anything in log_data)
		UNTYPED_LIST_ADD(logs, log.ui_data(user))

	var/list/data = list()
	data["logs"] = logs
	return data

/obj/item/darkpack/detective_scanner/ui_static_data(mob/user)
	var/list/categories = list()
	for(var/key,value in GLOB.detective_scan_categories)
		var/datum/detective_scan_category/category = value

		var/list/category_data = list()
		category_data["name"] = category.name
		category_data["uiIcon"] = category.ui_icon
		category_data["uiIconColor"] = category.ui_icon_color

		categories[category.id] = category_data

	var/list/data = list()
	data["categories"] = categories
	return data

/obj/item/darkpack/detective_scanner/ui_act(action, params, datum/tgui/ui)
	. = ..()
	if(.)
		return
	switch(action)
		if("clear")
			clear_logs(ui.user)
			ui.send_update()
		if("delete")
			var/index = params["index"] + 1
			if(!log_data[index])
				return
			if(scanner_busy)
				balloon_alert(ui.user, "scanner busy!")
				return
			log_data.Cut(index, index + 1)
			balloon_alert(ui.user, "log deleted")
			ui.send_update()
		if("print")
			if(!length(log_data))
				balloon_alert(ui.user, "no logs!")
				return
			if(scanner_busy)
				balloon_alert(ui.user, "scanner busy!")
				return
			scanner_busy = TRUE
			playsound(src, 'sound/machines/printer.ogg', 50)
			balloon_alert(ui.user, "printing report...")
			addtimer(CALLBACK(src, PROC_REF(safe_print_report)), 3 SECONDS)

/obj/item/darkpack/detective_scanner/proc/clear_logs(mob/living/user)
	if(!length(log_data))
		balloon_alert(user, "no logs!")
		return CLICK_ACTION_BLOCKING
	if(scanner_busy)
		balloon_alert(user, "scanner busy!")
		return CLICK_ACTION_BLOCKING
	balloon_alert(user, "logs cleared")
	log_data = list()
	return CLICK_ACTION_SUCCESS
