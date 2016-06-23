var/global/datum/controller/gameticker/ticker

#define GAME_STATE_PREGAME		1
#define GAME_STATE_SETTING_UP	2
#define GAME_STATE_PLAYING		3
#define GAME_STATE_FINISHED		4


/datum/controller/gameticker
	var/const/restart_timeout = 600
	var/current_state = GAME_STATE_PREGAME
	var/restart_called = 0

	var/hide_mode = 1
	var/datum/game_mode/mode = null
	var/game_start = 0 // world.time when the game started
	var/post_game = 0
	var/event_time = null
	var/event = 0

	var/login_music			// music played in pregame lobby

	var/list/datum/mind/minds = list()//The people in the game. Used for objective tracking.

	var/Bible_icon_state	// icon_state the chaplain has chosen for his bible
	var/Bible_item_state	// item_state the chaplain has chosen for his bible
	var/Bible_name			// name of the bible
	var/Bible_deity_name


	var/random_players = 0 	// if set to nonzero, ALL players who latejoin or declare-ready join will have random appearances/genders

	var/list/syndicate_coalition = list() // list of traitor-compatible factions
	var/list/factions = list()			  // list of all factions
	var/list/availablefactions = list()	  // list of factions with openings

	var/pregame_timeleft = 0

	var/delay_end = 0	//if set to nonzero, the round will not restart on it's own

	var/triai = 0//Global holder for Triumvirate

	var/round_end_announced = 0 // Spam Prevention. Announce round end only once.

/datum/controller/gameticker/proc/pregame()
	login_music = pick(\
	'sound/music/space_asshole.ogg',\
	'sound/music/space.ogg',\
	'sound/music/traitor.ogg',\
	'sound/music/title2.ogg',\
	'sound/music/clouds.s3m',\
	'sound/music/space_oddity.ogg',\
	'sound/music/lobby.ogg',\
	'sound/music/mining_song.ogg',\
	'sound/music/mining_song1.ogg',\
	'sound/music/mining_song2.ogg',\
	'sound/music/mining_song3.ogg',\
	'sound/music/jazzy_jazz.ogg',\
	)
	do
		pregame_timeleft = 180
		world << "<B><FONT color='blue'>Welcome to the pre-game lobby!</FONT></B>"
		world << "Please, setup your character and select ready. Game will start in [pregame_timeleft] seconds"
		while(current_state == GAME_STATE_PREGAME)
			for(var/i=0, i<10, i++)
				sleep(1)
				vote.process()
			if(going)
				pregame_timeleft--
			if(pregame_timeleft == config.vote_autogamemode_timeleft)
				if(!vote.time_remaining)
					vote.autogamemode()	//Quit calling this over and over and over and over.
					while(vote.time_remaining)
						for(var/i=0, i<10, i++)
							sleep(1)
							vote.process()
			if(pregame_timeleft <= 0)
				current_state = GAME_STATE_SETTING_UP
	while (!setup())


/datum/controller/gameticker/proc/setup()
	if(master_mode=="secret")
		src.hide_mode = 1

	var/list/runnable_modes = config.get_runnable_modes()
	if((master_mode=="random") || (master_mode=="secret"))
		if(!runnable_modes.len)
			current_state = GAME_STATE_PREGAME
			world << "<B>Unable to choose playable game mode.</B> Reverting to pre-game lobby."
			return 0

		if(secret_force_mode != "secret")
			src.mode = config.pick_mode(secret_force_mode)

		if(!src.mode)
			src.mode = pick_random_gamemode(runnable_modes)
	else
		src.mode = config.pick_mode(master_mode)

	if(!src.mode)
		current_state = GAME_STATE_PREGAME
		world << "<span class='danger'>Serious error in mode setup!</span> Reverting to pre-game lobby."
		return 0

	if(!src.mode.can_start())
		qdel(mode)
		/*
		var/totalPlayersReady = 0
		for(var/mob/new_player/player in player_list)
			if(player.ready)	totalPlayersReady++
		world << "<B><font color='blue'>Silly crew, you're missing [mode.required_players - totalPlayersReady] crew member(s) to play [mode.name].\nPicking random gamemode instead!</B></font>"
		*/
		current_state = GAME_STATE_PREGAME

		src.mode = pick_random_gamemode(runnable_modes)

	if(!hide_mode)
		src.mode.announce()

	job_master.ResetOccupations()
	job_master.DivideOccupations() // Apparently important for new antagonist system to register specific job antags properly.

	src.mode.persistant_antag_pre_setup() // Sets up persistant antags
	src.mode.pre_setup()

	create_characters() //Create player characters and transfer them
	collect_minds()
	equip_characters()

	setup_economy()
	current_state = GAME_STATE_PLAYING

	callHook("roundstart")

	shuttle_controller.setup_shuttle_docks()

	spawn(0)//Forking here so we dont have to wait for this to finish
		game_start = world.time
		mode.persistant_antag_post_setup()
		mode.post_setup()
		//Cleanup some stuff
		for(var/obj/effect/landmark/start/S in landmarks_list)
			//Deleting Startpoints but we need the ai point to AI-ize people later
			if (S.name != "AI")
				qdel(S)
		world << "<font color='blue'><B>Enjoy the game!</B></font>"
		world << "<h3>Today's date is [print_date( universe.date )]</h3>"
		world << sound('sound/AI/welcome.ogg') // Skie

	//start_events() //handles random events and space dust.
	//new random event system is handled from the MC.

	var/admins_number = 0
	for(var/client/C)
		if(C.holder)
			admins_number++
	if(admins_number == 0)
		send2adminirc("Round has started with no admins online.")

	processScheduler.start()

	for(var/obj/multiz/ladder/L in world)
		L.connect() //Lazy hackfix for ladders. TODO: move this to an actual controller. ~ Z

	if(config.sql_enabled)
		statistic_cycle() // Polls population totals regularly and stores them in an SQL DB -- TLE

	//god awful cheaky way of smoothing in-game movement
	config.Tickcomp = 0

	return 1

/datum/controller/gameticker
	//station_explosion used to be a variable for every mob's hud. Which was a waste!
	//Now we have a general cinematic centrally held within the gameticker....far more efficient!
	var/obj/screen/cinematic = null

	//Plus it provides an easy way to make cinematics for other events. Just use this as a template :)
	proc/station_explosion_cinematic(var/station_missed=0, var/override = null)
		if( cinematic )	return	//already a cinematic in progress!

		//initialise our cinematic screen object
		cinematic = new(src)
		cinematic.icon = 'icons/effects/station_explosion.dmi'
		cinematic.icon_state = "station_intact"
		cinematic.layer = 20
		cinematic.mouse_opacity = 0
		cinematic.screen_loc = "1,0"

		var/obj/structure/bed/temp_buckle = new(src)
		//Incredibly hackish. It creates a bed within the gameticker (lol) to stop mobs running around
		if(station_missed)
			for(var/mob/living/M in living_mob_list)
				M.buckled = temp_buckle				//buckles the mob so it can't do anything
				if(M.client)
					M.client.screen += cinematic	//show every client the cinematic
		else	//nuke kills everyone on z-level 1 to prevent "hurr-durr I survived"
			for(var/mob/living/M in living_mob_list)
				M.buckled = temp_buckle
				if(M.client)
					M.client.screen += cinematic

				switch(M.z)
					if(0)	//inside a crate or something
						var/turf/T = get_turf(M)
						if(T && T.z in overmap.station_levels)				//we don't use M.death(0) because it calls a for(/mob) loop and
							M.health = 0
							M.stat = DEAD
					if(1)	//on a z-level 1 turf.
						M.health = 0
						M.stat = DEAD

		//Now animate the cinematic
		switch(station_missed)
			if(1)	//nuke was nearby but (mostly) missed
				if( mode && !override )
					override = mode.name
				switch( override )
					if("mercenary") //Nuke wasn't on station when it blew up
						flick("intro_nuke",cinematic)
						sleep(35)
						world << sound('sound/effects/explosionfar.ogg')
						flick("station_intact_fade_red",cinematic)
						cinematic.icon_state = "summary_nukefail"
					else
						flick("intro_nuke",cinematic)
						sleep(35)
						world << sound('sound/effects/explosionfar.ogg')
						//flick("end",cinematic)


			if(2)	//nuke was nowhere nearby	//TODO: a really distant explosion animation
				sleep(50)
				world << sound('sound/effects/explosionfar.ogg')


			else	//station was destroyed
				if( mode && !override )
					override = mode.name
				switch( override )
					if("mercenary") //Nuke Ops successfully bombed the station
						flick("intro_nuke",cinematic)
						sleep(35)
						flick("station_explode_fade_red",cinematic)
						world << sound('sound/effects/explosionfar.ogg')
						cinematic.icon_state = "summary_nukewin"
					if("AI malfunction") //Malf (screen,explosion,summary)
						flick("intro_malf",cinematic)
						sleep(76)
						flick("station_explode_fade_red",cinematic)
						world << sound('sound/effects/explosionfar.ogg')
						cinematic.icon_state = "summary_malf"
					if("blob") //Station nuked (nuke,explosion,summary)
						flick("intro_nuke",cinematic)
						sleep(35)
						flick("station_explode_fade_red",cinematic)
						world << sound('sound/effects/explosionfar.ogg')
						cinematic.icon_state = "summary_selfdes"
					else //Station nuked (nuke,explosion,summary)
						flick("intro_nuke",cinematic)
						sleep(35)
						flick("station_explode_fade_red", cinematic)
						world << sound('sound/effects/explosionfar.ogg')
						cinematic.icon_state = "summary_selfdes"
				for(var/mob/living/M in living_mob_list)
					if(M.loc.z in overmap.station_levels)
						M.death()//No mercy
		//If its actually the end of the round, wait for it to end.
		//Otherwise if its a verb it will continue on afterwards.
		sleep(300)

		if(cinematic)	qdel(cinematic)		//end the cinematic
		if(temp_buckle)	qdel(temp_buckle)	//release everybody
		return


	proc/create_characters()
		for(var/mob/new_player/player in player_list)
			if(player && player.ready && player.mind)
				if(player.mind.assigned_role=="AI")
					player.close_spawn_windows()
					player.AIize()
				else if(!player.mind.assigned_role)
					continue
				else
					player.create_character()
					qdel(player)


	proc/collect_minds()
		for(var/mob/living/player in player_list)
			if(player.mind)
				ticker.minds += player.mind


	proc/equip_characters()
		for(var/mob/living/carbon/human/player in player_list)
			if(player && player.mind && player.mind.assigned_role)
				if(player.mind.assigned_role != "MODE")
					job_master.EquipRank(player, player.mind.assigned_role, 0)
					UpdateFactionList(player)
					EquipCustomItems(player)


	proc/process()
		if( current_state == GAME_STATE_FINISHED )
			if( restart_called )
				sleep(restart_timeout)
				if(!delay_end)
					world.Reboot()
				else
					world << "<span class='notice'><B>An admin has delayed the round end</B>. Retrying restart in [restart_timeout/10] seconds.</span>"

		if(current_state != GAME_STATE_PLAYING)
			return 0

		mode.process()
		process_newscaster()

		emergency_shuttle.process()

		var/game_finished = 0
		var/mode_finished = 0
		if (config.continous_rounds)
			game_finished = (emergency_shuttle.returned() || mode.station_was_nuked)
			mode_finished = (!post_game && mode.check_finished())
		else
			game_finished = (mode.check_finished() || (emergency_shuttle.returned() && emergency_shuttle.evac == 1))
			mode_finished = game_finished

		if(!mode.explosion_in_progress && game_finished && (mode_finished || post_game))
			current_state = GAME_STATE_FINISHED

			spawn
				declare_completion()

			spawn(50)
				callHook("roundend")

				if( blackbox )
					blackbox.save_all_data_to_sql()

				if( config.canon )
					canonHandleRoundEnd()

				if (mode.station_was_nuked)
					feedback_set_details("end_proper","nuke")
					if(!delay_end)
						world << "<span class='notice'><B>Rebooting due to destruction of station in [restart_timeout/10] seconds</B></span>"
				else
					feedback_set_details("end_proper","proper completion")
					world << "<span class='notice'><B>The game is now over. The round will restart in 60 seconds.</B></span>"
					if(!restart_called)
						restart_called = 1

		else if (mode_finished)
			post_game = 1

			mode.cleanup()

			//call a transfer shuttle vote
			spawn(50)
				if(!round_end_announced) // Spam Prevention. Now it should announce only once.
					world << "<span class='alert'>The round has ended!</span>"
					round_end_announced = 1
				vote.autotransfer()

		return 1

	proc/getfactionbyname(var/name)
		for(var/datum/faction/F in factions)
			if(F.name == name)
				return F


/datum/controller/gameticker/proc/declare_completion()
	world << "<br><br><br><H1>A round of [mode.name] has ended!</H1>"
	for(var/mob/Player in player_list)
		if(Player.mind && !isnewplayer(Player))
			if(Player.stat != DEAD)
				var/turf/playerTurf = get_turf(Player)
				if(emergency_shuttle.departed && emergency_shuttle.evac)
					if(isNotAdminLevel(playerTurf.z))
						Player << "<font color='blue'><b>You managed to survive, but were marooned on [station_name()] as [Player.real_name]...</b></font>"
					else
						Player << "<font color='green'><b>You managed to survive the events on [station_name()] as [Player.real_name].</b></font>"
				else if(isAdminLevel(playerTurf.z))
					Player << "<font color='green'><b>You successfully underwent crew transfer after events on [station_name()] as [Player.real_name].</b></font>"
				else if(issilicon(Player))
					Player << "<font color='green'><b>You remain operational after the events on [station_name()] as [Player.real_name].</b></font>"
				else
					Player << "<font color='blue'><b>You missed the crew transfer after the events on [station_name()] as [Player.real_name].</b></font>"
			else
				if(istype(Player,/mob/dead/observer))
					var/mob/dead/observer/O = Player
					if(!O.started_as_observer)
						Player << "<font color='red'><b>You did not survive the events on [station_name()]...</b></font>"
				else
					Player << "<font color='red'><b>You did not survive the events on [station_name()]...</b></font>"
	world << "<br>"

	for (var/mob/living/silicon/ai/aiPlayer in mob_list)
		if (aiPlayer.stat != 2)
			world << "<b>[aiPlayer.name] (Played by: [aiPlayer.key])'s laws at the end of the round were:</b>"
		else
			world << "<b>[aiPlayer.name] (Played by: [aiPlayer.key])'s laws when it was deactivated were:</b>"
		aiPlayer.show_laws(1)

		if (aiPlayer.connected_robots.len)
			var/robolist = "<b>The AI's loyal minions were:</b> "
			for(var/mob/living/silicon/robot/robo in aiPlayer.connected_robots)
				robolist += "[robo.name][robo.stat?" (Deactivated) (Played by: [robo.key]), ":" (Played by: [robo.key]), "]"
			world << "[robolist]"

	var/dronecount = 0

	for (var/mob/living/silicon/robot/robo in mob_list)

		if(istype(robo,/mob/living/silicon/robot/drone))
			dronecount++
			continue

		if (!robo.connected_ai)
			if (robo.stat != 2)
				world << "<b>[robo.name] (Played by: [robo.key]) survived as an AI-less borg! Its laws were:</b>"
			else
				world << "<b>[robo.name] (Played by: [robo.key]) was unable to survive the rigors of being a cyborg without an AI. Its laws were:</b>"

			if(robo) //How the hell do we lose robo between here and the world messages directly above this?
				robo.laws.show_laws(world)

	if(dronecount)
		world << "<b>There [dronecount>1 ? "were" : "was"] [dronecount] industrious maintenance [dronecount>1 ? "drones" : "drone"] at the end of this round."

	mode.declare_completion()//To declare normal completion.

	//calls auto_declare_completion_* for all modes
	for(var/handler in typesof(/datum/game_mode/proc))
		if (findtext("[handler]","auto_declare_completion_[mode.name]"))
			call(mode, handler)()

	//Ask the event manager to print round end information
	event_manager.RoundEnd()

	mode.persistant_antag_game_end() // After-the-game persistant antag stuff

	//Print a list of antagonists to the server log
	var/list/total_antagonists = list()
	//Look into all mobs in world, dead or alive
	for(var/datum/mind/Mind in minds)
		var/datum/antagonist/antag = Mind.antagonist
		if(antag)							//if they are an antagonist of some sort.
			if(antag.name in total_antagonists)	//If the role exists already, add the name to it
				total_antagonists[antag.name] += ", [Mind.name]([Mind.key])"
			else
				total_antagonists.Add(antag.name) //If the role doesnt exist in the list, create it and add the mob
				total_antagonists[antag.name] += ": [Mind.name]([Mind.key])"

	//Now print them all into the log!
	log_game("Antagonists at round end were...")
	for(var/i in total_antagonists)
		log_game("[i]s[total_antagonists[i]].")

	statistics.call_stats() // Show the end-round stats

	// End-round antag voting
	var/list/datum/mind/all_antagonists = list()
	//Look into all mobs in world, dead or alive
	for(var/datum/mind/M in minds)
		if(( M.current && M.current.client ) && M.antagonist && !istype(M.antagonist, /datum/antagonist/traitor/persistant)) // Players that have left can't get commendations
			all_antagonists += M

	if(all_antagonists.len)
		world << "<span class='notice'><B>Please vote on the antagonists' performance!</B></span>"
	else
		testing( "There were no antagonists." )
		return 1

	for(var/mob/M in player_list)
		if(M.client)
			testing( "Opening antag vote for [M.client]" )
			var/datum/browser/menu = new( null, "antag_vote", "Antagonist Vote", 500, 700)
			open_antag_vote( M, menu, all_antagonists.Copy() ) // defined in modules/antagonist/menus/voting.dm

	return 1

/proc/pick_random_gamemode(runnable_modes)
	var/list/weighted_modes = list()
	for(var/datum/game_mode/GM in runnable_modes)
		weighted_modes[GM.config_tag] = config.probabilities[GM.config_tag]
	return gamemode_cache[pickweight(weighted_modes)]
