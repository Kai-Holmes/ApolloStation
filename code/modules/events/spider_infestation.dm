/var/global/sent_spiders_to_station = 0

/datum/event/spider_infestation
	announceWhen	= 400

	var/spawncount = 1


/datum/event/spider_infestation/setup()
	announceWhen = rand(announceWhen, announceWhen + 50)
	spawncount = rand(8, 12)	//spiderlings only have a 50% chance to grow big and strong
	sent_spiders_to_station = 0

/datum/event/spider_infestation/announce()
	command_announcement.Announce("Unidentified lifesigns detected aboard [station_name()]. Engineering personnel are required to secure any exterior access, including ducting and ventilation.", "AUTOMATED ALERT: Unidentified Lifesigns", new_sound = 'sound/AI/aliens.ogg')

/datum/event/spider_infestation/start()
	var/list/vents = list()
	for(var/obj/machinery/atmospherics/unary/vent_pump/temp_vent in world)
		if(!temp_vent.welded && temp_vent.network && temp_vent.loc.z in config.station_levels)
			if(temp_vent.network.normal_members.len > 50)
				vents += temp_vent

	while((spawncount >= 1) && vents.len)
		var/obj/vent = pick(vents)
		new /obj/effect/spider/spiderling(vent.loc)
		vents -= vent
		spawncount--