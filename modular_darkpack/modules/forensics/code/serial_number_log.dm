/obj/effect/mapping_helpers/serial_number_log
	name = "Gun serial ref sheet landmark"
	desc = "Checks all the guns in the placed area then prints their name and numbers on a generated piece of paper!"
	delete_after_roundstart = TRUE

// Needs to load AFTER everything else so it properly checks guns in the defined area.
/obj/effect/mapping_helpers/serial_number_log/Initialize()
	..()
	. = INITIALIZE_HINT_LATELOAD

/obj/effect/mapping_helpers/serial_number_log/LateInitialize()
	. = ..()
	var/area/our_area = get_area(src)
	var/text = "Armoury Firearm Serial Numbers - Master List \n"
	for(var/obj/item/gun/firearm in our_area.contents)
		if(firearm.serial_type)
			text += "[firearm.serial_type] - [firearm.name] \n"
	new /obj/item/paper(get_turf(src), text, "Armoury log")
