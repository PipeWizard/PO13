/mob/living/Life()
	set invisibility = 0
	set background = BACKGROUND_ENABLED

	..()

	if (HasMovementHandler(/datum/movement_handler/mob/transformation/))
		return
	if (!loc)
		return

	if(machine && (machine.CanUseTopic(src, machine.DefaultTopicState()) == STATUS_CLOSE)) // unsure if this is a good idea, but using canmousedrop was ???
		machine = null

	//Handle temperature/pressure differences between body and environment
	handle_environment(loc.return_air())

	blinded = 0 // Placing this here just show how out of place it is.
	// human/handle_regular_status_updates() needs a cleanup, as blindness should be handled in handle_disabilities()
	handle_regular_status_updates() // Status & health update, are we dead or alive etc.

	if(stat != DEAD)
		aura_check(AURA_TYPE_LIFE)

	//Check if we're on fire
	handle_fire()

	for(var/obj/item/grab/G in get_active_grabs())
		G.Process()

	handle_actions()

	UpdateLyingBuckledAndVerbStatus()

	handle_regular_hud_updates()

	handle_status_effects()

	return 1

/mob/living/proc/handle_breathing()
	return

/mob/living/proc/handle_mutations_and_radiation()
	return

// Get valid, unique reagent holders for metabolizing. Avoids metabolizing the same holder twice in a tick.
/mob/living/proc/get_unique_metabolizing_reagent_holders()
	for(var/datum/reagents/metabolism/holder in list(get_contact_reagents(), get_ingested_reagents(), get_injected_reagents(), get_inhaled_reagents()))
		LAZYDISTINCTADD(., holder)

/mob/living/proc/handle_chemicals_in_body()
	SHOULD_CALL_PARENT(TRUE)
	chem_effects = null

	// TODO: handle isSynthetic() properly via Psi's metabolism modifiers for contact reagents like acid.
	if((status_flags & GODMODE) || isSynthetic())
		return FALSE

	// Metabolize any reagents currently in our body and keep a reference for chem dose checking.
	var/list/metabolizing_holders = get_unique_metabolizing_reagent_holders()
	if(length(metabolizing_holders))
		var/list/tick_dosage_tracker = list() // Used to check if we're overdosing on anything.
		for(var/datum/reagents/metabolism/holder as anything in metabolizing_holders)
			holder.metabolize(tick_dosage_tracker)
		// Check for overdosing.
		var/size_modifier = (MOB_SIZE_MEDIUM / mob_size)
		for(var/decl/material/R as anything in tick_dosage_tracker)
			if(tick_dosage_tracker[R] > (R.overdose * ((R.flags & IGNORE_MOB_SIZE) ? 1 : size_modifier)))
				R.affect_overdose(src)

	// Update chem dosage.
	// TODO: refactor chem dosage above isSynthetic() and GODMODE checks.
	if(length(chem_doses))
		for(var/T in chem_doses)

			var/still_processing_reagent = FALSE
			for(var/datum/reagents/holder as anything in metabolizing_holders)
				if(holder.has_reagent(T))
					still_processing_reagent = TRUE
					break
			if(still_processing_reagent)
				continue
			var/decl/material/R = GET_DECL(T)
			var/dose = LAZYACCESS(chem_doses, T) - R.metabolism*2
			LAZYSET(chem_doses, T, dose)
			if(LAZYACCESS(chem_doses, T) <= 0)
				LAZYREMOVE(chem_doses, T)

	if(apply_chemical_effects())
		updatehealth()

	return TRUE

/mob/living/proc/apply_chemical_effects()
	var/burn_regen = GET_CHEMICAL_EFFECT(src, CE_REGEN_BURN)
	var/brute_regen = GET_CHEMICAL_EFFECT(src, CE_REGEN_BRUTE)
	if(burn_regen || brute_regen)
		heal_organ_damage(brute_regen, burn_regen)
		return TRUE


/mob/living/proc/handle_random_events()
	return

/mob/living
	var/weakref/last_weather

/mob/living/proc/is_outside()
	var/turf/T = loc
	return istype(T) && T.is_outside()

/mob/living/proc/get_affecting_weather()
	var/turf/my_turf = get_turf(src)
	if(!istype(my_turf))
		return
	var/turf/actual_loc = loc
	// If we're standing in the rain, use the turf weather.
	. = istype(actual_loc) && actual_loc.weather
	if(!.) // If we're under or inside shelter, use the z-level rain (for ambience)
		. = global.weather_by_z["[my_turf.z]"]

/mob/living/proc/handle_environment(var/datum/gas_mixture/environment)

	SHOULD_CALL_PARENT(TRUE)

	// Handle physical effects of weather.
	var/decl/state/weather/weather_state
	var/obj/abstract/weather_system/weather = get_affecting_weather()
	if(weather)
		weather_state = weather.weather_system.current_state
		if(istype(weather_state))
			weather_state.handle_exposure(src, get_weather_exposure(weather), weather)

	// Refresh weather ambience.
	// Show messages and play ambience.
	if(client && get_preference_value(/datum/client_preference/play_ambiance) == PREF_YES)

		// Work out if we need to change or cancel the current ambience sound.
		var/send_sound
		var/mob_ref = weakref(src)
		if(istype(weather_state))
			var/ambient_sounds = !is_outside() ? weather_state.ambient_indoors_sounds : weather_state.ambient_sounds
			var/ambient_sound = length(ambient_sounds) && pick(ambient_sounds)
			if(global.current_mob_ambience[mob_ref] == ambient_sound)
				return
			send_sound = ambient_sound
			global.current_mob_ambience[mob_ref] = send_sound
		else if(mob_ref in global.current_mob_ambience)
			global.current_mob_ambience -= mob_ref
		else
			return

		// Push sound to client. Pipe dream TODO: crossfade between the new and old weather ambience.
		sound_to(src, sound(null, repeat = 0, wait = 0, volume = 0, channel = sound_channels.weather_channel))
		if(send_sound)
			sound_to(src, sound(send_sound, repeat = TRUE, wait = 0, volume = 30, channel = sound_channels.weather_channel))

//This updates the health and status of the mob (conscious, unconscious, dead)
/mob/living/proc/handle_regular_status_updates()
	updatehealth()
	if(stat != DEAD)
		if(HAS_STATUS(src, STAT_PARA))
			set_stat(UNCONSCIOUS)
		else if (status_flags & FAKEDEATH)
			set_stat(UNCONSCIOUS)
		else
			set_stat(CONSCIOUS)
		return 1

/mob/living/proc/handle_disabilities()
	handle_impaired_vision()
	handle_impaired_hearing()

/mob/living/proc/handle_impaired_vision()
	if((sdisabilities & BLINDED) || stat) //blindness from disability or unconsciousness doesn't get better on its own
		SET_STATUS_MAX(src, STAT_BLIND, 2)

/mob/living/proc/handle_impaired_hearing()
	if((sdisabilities & DEAFENED) || stat) //disabled-deaf, doesn't get better on its own
		SET_STATUS_MAX(src, STAT_TINNITUS, 1)

//this handles hud updates. Calls update_vision() and handle_hud_icons()
/mob/living/proc/handle_regular_hud_updates()
	if(!client)	return 0

	handle_hud_icons()
	handle_vision()
	handle_low_light_vision()

	return 1

/mob/living/proc/handle_low_light_vision()

	// No client means nothing to update.
	if(!client || !lighting_master)
		return

	// No loc or species means we should just assume no adjustment.
	var/decl/species/species = get_species()
	var/turf/my_turf = get_turf(src)
	if(!isturf(my_turf) || !species)
		lighting_master.set_alpha(255)
		return

	// TODO: handling for being inside atoms.
	var/target_value = 255 * (1-species.base_low_light_vision)
	var/loc_lumcount = my_turf.get_lumcount()
	if(loc_lumcount < species.low_light_vision_threshold)
		target_value = round(target_value * (1-species.low_light_vision_effectiveness))

	if(lighting_master.alpha == target_value)
		return

	var/difference = round((target_value-lighting_master.alpha) * species.low_light_vision_adjustment_speed)
	if(abs(difference) > 1)
		target_value = lighting_master.alpha + difference
	lighting_master.set_alpha(target_value)

/mob/living/proc/handle_vision()
	update_sight()

	if(stat == DEAD)
		return

	if(GET_STATUS(src, STAT_BLIND))
		overlay_fullscreen("blind", /obj/screen/fullscreen/blind)
	else
		clear_fullscreen("blind")
		set_fullscreen(disabilities & NEARSIGHTED, "impaired", /obj/screen/fullscreen/impaired, 1)
		set_fullscreen(GET_STATUS(src, STAT_BLURRY), "blurry", /obj/screen/fullscreen/blurry)
		set_fullscreen(GET_STATUS(src, STAT_DRUGGY), "high", /obj/screen/fullscreen/high)

	set_fullscreen(stat == UNCONSCIOUS, "blackout", /obj/screen/fullscreen/blackout)

	if(machine)
		var/viewflags = machine.check_eye(src)
		if(viewflags < 0)
			reset_view(null, 0)
		else if(viewflags)
			set_sight(viewflags)
	else if(eyeobj)
		if(eyeobj.owner != src)
			reset_view(null)
	else if(z_eye)
		return
	else if(client && !client.adminobs)
		reset_view(null)

/mob/living/proc/update_sight()
	set_sight(0)
	set_see_in_dark(0)
	if(stat == DEAD || (eyeobj && !eyeobj.living_eye))
		update_dead_sight()
	else
		update_living_sight()

	var/list/vision = get_accumulated_vision_handlers()
	set_sight(sight | vision[1])
	set_see_invisible(max(vision[2], see_invisible))

/mob/living/proc/update_living_sight()
	var/set_sight_flags = sight & ~(SEE_TURFS|SEE_MOBS|SEE_OBJS)
	if(stat & UNCONSCIOUS)
		set_sight_flags |= BLIND
	else
		set_sight_flags &= ~BLIND

	set_sight(set_sight_flags)
	set_see_in_dark(initial(see_in_dark))
	set_see_invisible(initial(see_invisible))

/mob/living/proc/update_dead_sight()
	set_sight(sight|SEE_TURFS|SEE_MOBS|SEE_OBJS)
	set_see_in_dark(8)
	set_see_invisible(SEE_INVISIBLE_LEVEL_TWO)

/mob/living/proc/handle_hud_icons()
	handle_hud_icons_health()
	handle_hud_glasses()

/mob/living/proc/handle_hud_icons_health()
	return
