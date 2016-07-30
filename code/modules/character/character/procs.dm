/proc/checkCharacter( var/character_ident, var/ckey )
	establish_db_connection()
	if( !dbcon.IsConnected() )
		return 0

	if( !ckey )
		return 0

	if( !character_ident )
		return 0

	var/sql_ckey = ckey( ckey )
	var/sql_character_ident = html_encode( character_ident )

	var/DBQuery/query = dbcon.NewQuery("SELECT id FROM characters WHERE ckey = '[sql_ckey]' AND id = '[sql_character_ident]'")
	if( !query.Execute() )
		return 0

	if( !query.NextRow() )
		return 0

	var/sql_id = query.item[1]

	if(!sql_id)
		return 0

	if(istext(sql_id))
		sql_id = text2num(sql_id)

	if(!isnum(sql_id))
		return 0

	return sql_id

/datum/character/New( key = "", new_char = 1, temp = 1, acc = null )
	ckey = ckey( key )

	blood_type = pick(4;"O-", 36;"O+", 3;"A-", 28;"A+", 1;"B-", 20;"B+", 1;"AB-", 5;"AB+")

	gender = pick(MALE, FEMALE)
	name = random_name(gender,species)

	gear = list()

	DNA = md5( "DNA[name][blood_type][gender][eye_color][time2text(world.timeofday,"hh:mm")]" )
	fingerprints = md5( DNA )

	new_character = new_char
	temporary = temp

	change_age( 30 )

	account = acc

	if( account && !account.department )
		account.LoadDepartment( CIVILIAN )

	menu = new( null, "creator", "Character Creator", 710, 610 )
	menu.window_options = "focus=0;can_close=0;"

	all_characters += src

	..()

/datum/character/Destroy()
	all_characters -= src

	..()

/datum/character/proc/copy_to( mob/living/carbon/human/character )
	if( !istype( character ))
		return

	if(config.humans_need_surnames)
		var/firstspace = findtext(name, " ")
		var/name_length = length(name)
		if(!firstspace)	//we need a surname
			name += " [pick(last_names)]"
		else if(firstspace == name_length)
			name += "[pick(last_names)]"

	char_mob = character

	character.gender = gender
	character.real_name = name
	character.name = character.real_name
	if(character.dna)
		character.dna.real_name = character.real_name

	character.character = src

	character.set_species( species, 1 )

	// Destroy/cyborgize organs
	for(var/name in organ_data)
		var/status = organ_data[name]
		var/datum/organ/external/O = character.organs_by_name[name]
		if(O)
			if(status == "amputated")
				O.amputated = 1
				O.status |= ORGAN_DESTROYED
				O.destspawn = 1
			else if(status == "cyborg")
				O.status |= ORGAN_ROBOT
		else
			var/datum/organ/internal/I = character.internal_organs_by_name[name]
			if(I)
				if(status == "assisted")
					I.mechassist()
				else if(status == "mechanical")
					I.mechanize()

	if(underwear > underwear_m.len || underwear < 1)
		underwear = 0 //I'm sure this is 100% unnecessary, but I'm paranoid... sue me. //HAH NOW NO MORE MAGIC CLONING UNDIES

	if(undershirt > undershirt_t.len || undershirt < 1)
		undershirt = 0

	if(backpack > 4 || backpack < 1)
		backpack = 1 //Same as above

	//Debugging report to track down a bug, which randomly assigned the plural gender to people.
	if(gender in list(PLURAL, NEUTER))
		if(isliving(character)) //Ghosts get neuter by default
			message_admins("[character] ([character.ckey]) has spawned with their gender as plural or neuter. Please notify coders.")
			gender = MALE

	account.copyFrom( src )
	enterMob()

/datum/character/proc/getCharID()
	establish_db_connection()
	if( !dbcon.IsConnected() )
		return 0

	var/DBQuery/query = dbcon.NewQuery("SELECT id FROM characters WHERE name = '[html_encode( sql_sanitize_text( name ))]' AND ckey = '[ckey( ckey )]'")
	query.Execute()
	var/sql_id = 0
	while(query.NextRow())
		sql_id = query.item[1]
		break

	if(sql_id)
		if(istext(sql_id))
			sql_id = text2num(sql_id)
		if(!isnum(sql_id))
			return 0

	return sql_id

/datum/character/proc/saveAll( prompt = 0, force = 0 )
	if( prompt && usr )
		var/response
		if( new_character )
			response = alert(usr, "Are you sure you're finished with character setup? You will no longer be able to change your character name, age, gender, or species after this.", "Save Character","Yes","No")
		else
			response = alert(usr, "Are you sure you want to save?", "Save Character","Yes","No")

		if( response == "No" )
			return 1

	if( !saveCharacter( force ))
		return 0

	if( !account.saveAccount( force ))
		return 0

	return 1

/datum/character/proc/saveCharacter( var/force = 0 )
	if( istype( char_mob ))
		char_mob.fully_replace_character_name( char_mob.real_name, name )
		copy_to( char_mob )
		char_mob.update_hair()
		char_mob.update_body()
		char_mob.check_dna( char_mob )

	if(( temporary && account.crew ) || ( temporary && !force )) // If we're just a temporary character and the user isnt forcing this save, dont save to database
		return 1

	establish_db_connection()
	if( !dbcon.IsConnected() )
		log_debug( "SAVE CHARACTER: Didn't save [name] / ([ckey]) because the database wasn't connected" )
		return 0

	if( !ckey && !force )
		log_debug( "SAVE CHARACTER: Didn't save [name] because they didn't have a ckey" )
		return 0

	if ( IsGuestKey( ckey ) && !force )
		log_debug( "SAVE CHARACTER: Didn't save [name] / ([ckey]) because they were a guest character" )
		return 0

	var/list/variables = list()

	variables["ckey"] = ckey( ckey )
	variables["name"] = html_encode( sql_sanitize_text( name ))
	variables["gender"] = html_encode( sql_sanitize_text( gender ))
	variables["birth_date"] = html_encode( list2params( birth_date ))

	// Default clothing

	var/list/underwear_options
	if(gender == MALE)
		underwear_options = underwear_m
	else
		underwear_options = underwear_f

	variables["underwear"] = sanitize_integer( underwear, 1, underwear_options.len, initial(underwear))
	variables["undershirt"] = sanitize_integer( undershirt, 1, undershirt_t.len, initial(undershirt))
	variables["backpack"] = sanitize_integer( backpack, 1, backpacklist.len, initial(backpack))

	// Cosmetic features
	variables["hair_style"] = html_encode( sql_sanitize_text( hair_style ))
	variables["hair_face_style"] = html_encode( sql_sanitize_text( hair_face_style ))

	variables["hair_color"] = sanitize_hexcolor( hair_color )
	variables["hair_face_color"] = sanitize_hexcolor( hair_face_color )

	variables["skin_tone"] = sanitize_integer( skin_tone, SKIN_TONE_DEFAULT-SKIN_TONE_MAX, SKIN_TONE_DEFAULT-SKIN_TONE_MIN, SKIN_TONE_DEFAULT )
	variables["skin_color"] = sanitize_hexcolor( skin_color )

	variables["eye_color"] = sanitize_hexcolor( eye_color )

	// Character species
	variables["species"] = html_encode( sql_sanitize_text( species ))

	// Secondary language
	var/datum/language/L = additional_language
	if( istype( L ))
		variables["additional_language"] = html_encode( sql_sanitize_text( L.name ))

	// Custom spawn gear
	variables["gear"] = html_encode( list2params( gear ))

	// Maps each organ to either null(intact), "cyborg" or "amputated"
	// will probably not be able to do this for head and torso ;)
	variables["organ_data"] = html_encode( list2params( organ_data ))

	// Flavor texts
	variables["flavor_texts_human"] = html_encode( sql_sanitize_text( flavor_texts_human ))
	variables["flavor_texts_robot"] = html_encode( sql_sanitize_text( flavor_texts_robot ))

	// Character disabilities
	variables["disabilities"] = sanitize_integer( disabilities, 0, BITFLAGS_MAX, 0 )

	// Unique identifiers
	variables["DNA"] = html_encode( sql_sanitize_text( DNA ))
	variables["fingerprints"] = html_encode( sql_sanitize_text( fingerprints ))
	variables["blood_type"] = html_encode( sql_sanitize_text( blood_type ))

	var/list/names = list()
	var/list/values = list()
	for( var/name in variables )
		names += sql_sanitize_text( name )
		values += variables[name]

	id = getCharID()

	if(id)
		if( names.len != values.len )
			log_debug( "SAVE CHARACTER: Didn't save [name] / ([ckey]) because the variables length did not match the values" )
			return 0

		var/query_params = ""
		for( var/i = 1; i <= names.len; i++ )
			query_params += "[names[i]]='[values[i]]'"
			if( i != names.len )
				query_params += ","

		var/DBQuery/query_update = dbcon.NewQuery("UPDATE characters SET [query_params] WHERE id = '[id]'")
		if( !query_update.Execute())
			log_debug( "SAVE CHARACTER: Didn't save [name] / ([ckey]) because the SQL update failed" )
			return 0
	else
		var/query_names = list2text( names, "," )
		query_names += sql_sanitize_text( ", id" )

		var/query_values = list2text( values, "','" )
		query_values += "', null"

		// This needs a single quote before query_values because otherwise there will be an odd number of single quotes
		var/DBQuery/query_insert = dbcon.NewQuery("INSERT INTO characters ([query_names]) VALUES ('[query_values])")
		if( !query_insert.Execute() )
			log_debug( "SAVE CHARACTER: Didn't save [name] / ([ckey]) because the SQL insert failed" )
			return 0

		id = getCharID()

	if( new_character || force )
		account.copyFrom( src )

	new_character = 0

	return id

/datum/character/proc/loadCharacter( var/character_ident )
	if( !character_ident )
		log_debug( "No character identity!" )
		return 0

	if( ckey && !checkCharacter( character_ident, ckey ))
		log_debug( "Character does not belong to the given ckey!" )
		return 0

	establish_db_connection()
	if( !dbcon.IsConnected() )
		log_debug( "Database is not connected!" )
		return 0

	var/list/variables = list()

	variables["name"] = "text"
	variables["gender"] = "text"
	variables["birth_date"] = "birth_date"

	variables["underwear"] = "number"
	variables["undershirt"] = "number"
	variables["backpack"] = "number"

	// Cosmetic features
	variables["hair_style"] = "text"
	variables["hair_face_style"] = "text"

	variables["hair_color"] = "text"
	variables["hair_face_color"] = "text"

	variables["skin_tone"] = "number"
	variables["skin_color"] = "text"

	variables["eye_color"] = "text"

	// Character species
	variables["species"] = "text"

	// Secondary language
	variables["additional_language"] = "language"

	// Custom spawn gear
	variables["gear"] = "params"

	// Maps each organ to either null(intact), "cyborg" or "amputated"
	// will probably not be able to do this for head and torso ;)
	variables["organ_data"] = "params"

	// Flavor texts
	variables["flavor_texts_human"] = "text"
	variables["flavor_texts_robot"] = "text"

	// Character disabilities
	variables["disabilities"] = "number"

	// Unique identifiers
	variables["DNA"] = "text"
	variables["fingerprints"] = "text"
	variables["blood_type"] = "text"

	var/query_names = list2text( variables, "," )

	new_character = 0 // If we're loading from the database, we're obviously a pre-existing character
	temporary = 1 // All characters are temporary until they enter the game

	var/DBQuery/query = dbcon.NewQuery("SELECT [query_names] FROM characters WHERE id = '[character_ident]'")
	if( !query.Execute() )
		log_debug( "Could not execute query!" )
		return 0

	if( !query.NextRow() )
		log_debug( "Query has no data!" )
		return 0

	for( var/i = 1; i <= variables.len; i++ )
		var/value = query.item[i]

		switch( variables[variables[i]] )
			if( "text" )
				value = html_decode( sanitize_text( value, "ERROR" ))
			if( "number" )
				value = text2num( value )
			if( "params" )
				value = params2list( html_decode( value ))
				if( !value )
					value = list()
			if( "list" )
				value = text2list( html_decode( value ))
				if( !value )
					value = list()
			if( "language" )
				if( value in all_languages )
					value = all_languages[value]
				else
					value = "None"
			if( "birth_date" )
				birth_date = params2list( html_decode( value ))

				var/randomize = 0

				for( var/j in birth_date )
					if( birth_date[j] )
						birth_date[j] = text2num( birth_date[j] )
					else
						randomize = 1

				if( !birth_date || !birth_date.len == 3 )
					randomize = 1

				if( randomize )
					change_age( rand( 25, 45 ))

				calculate_age()
				continue

		vars[variables[i]] = value

	return 1

/datum/character/proc/randomize_appearance( var/random_age = 0 )
	skin_tone = random_skin_tone()
	hair_style = random_hair_style(gender, species)
	hair_face_style = random_facial_hair_style(gender, species)
	if(species != "Machine")
		randomize_hair_color("hair")
		randomize_hair_color("facial")
	randomize_eyes_color()
	randomize_skin_color()
	underwear = rand(1,underwear_m.len)
	undershirt = rand(1,undershirt_t.len)
	backpack = 2
	if( random_age )
		age = rand(AGE_MIN,AGE_MAX)

/proc/randomize_appearance_for(var/mob/living/carbon/human/H)
	if( !istype( H ))
		return

	H.character.randomize_appearance(1)
	H.character.copy_to(H,1)

/datum/character/proc/randomize_hair_color(var/target = "hair")
	if(prob (75) && target == "facial") // Chance to inherit hair color
		hair_face_color = hair_color
		return

	var/red
	var/green
	var/blue

	var/col = pick ("blonde", "black", "chestnut", "copper", "brown", "wheat", "old")
	switch(col)
		if("blonde")
			red = 255
			green = 255
			blue = 0
		if("black")
			red = 0
			green = 0
			blue = 0
		if("chestnut")
			red = 153
			green = 102
			blue = 51
		if("copper")
			red = 255
			green = 153
			blue = 0
		if("brown")
			red = 102
			green = 51
			blue = 0
		if("wheat")
			red = 255
			green = 255
			blue = 153
		if("old")
			red = rand (100, 255)
			green = red
			blue = red
/* those darn kids and their skateboards
		if("punk")
			red = rand (0, 255)
			green = rand (0, 255)
			blue = rand (0, 255)
*/

	red = max(min(red + rand (-25, 25), 255), 0)
	green = max(min(green + rand (-25, 25), 255), 0)
	blue = max(min(blue + rand (-25, 25), 255), 0)

	switch(target)
		if("hair")
			hair_color = rgb( red, green, blue )
		if("facial")
			hair_face_color = rgb( red, green, blue )

// Call this to change the character's age, will recalculate their birthday given an age
/datum/character/proc/change_age( var/new_age, var/age_min = AGE_MIN, var/age_max = AGE_MAX )
	new_age = max( min( round( new_age ), age_max), age_min)

	var/birth_year = game_year-new_age

	var/birth_month = text2num(time2text(world.timeofday, "MM")) - rand( 1, 12 )

	if( birth_month < 1 )
		birth_year++
		birth_month += 12

	var/birth_day = rand( 1, getMonthDays( birth_month ))

	birth_date = list( "year" = birth_year, "month" = birth_month, "day" = birth_day )
	age = calculate_age()

// Calculates the characters age from their birthdate
/datum/character/proc/calculate_age()
	var/cur_year = game_year
	var/cur_month = text2num(time2text(world.timeofday, "MM"))
	var/cur_day = text2num(time2text(world.timeofday, "DD"))

	if( !birth_date || birth_date.len < 3 )
		change_age( rand( 20, 50 )) // If we dont have a birthdate, we better get one

	var/birth_year = birth_date["year"]
	var/birth_month = birth_date["month"]
	var/birth_day = birth_date["day"]

	age = ( cur_year-birth_year )+1

	if( cur_month > birth_month )
		age++
	else if( cur_month == birth_month )
		if( cur_day >= birth_day )
			age++

	return age

// Prints the character's birthdate in a readable format
/datum/character/proc/print_birthdate()
	if( !birth_date || birth_date.len < 3 )
		calculate_age()
	return print_date( birth_date )

/datum/character/proc/randomize_eyes_color()
	var/red
	var/green
	var/blue

	var/col = pick ("black", "grey", "brown", "chestnut", "blue", "lightblue", "green", "albino")
	switch(col)
		if("black")
			red = 0
			green = 0
			blue = 0
		if("grey")
			red = rand (100, 200)
			green = red
			blue = red
		if("brown")
			red = 102
			green = 51
			blue = 0
		if("chestnut")
			red = 153
			green = 102
			blue = 0
		if("blue")
			red = 51
			green = 102
			blue = 204
		if("lightblue")
			red = 102
			green = 204
			blue = 255
		if("green")
			red = 0
			green = 102
			blue = 0
		if("albino")
			red = rand (200, 255)
			green = rand (0, 150)
			blue = rand (0, 150)

	red = max(min(red + rand (-25, 25), 255), 0)
	green = max(min(green + rand (-25, 25), 255), 0)
	blue = max(min(blue + rand (-25, 25), 255), 0)

	eye_color = rgb( red, green, blue )

/datum/character/proc/randomize_skin_color()
	var/red
	var/green
	var/blue

	var/col = pick ("black", "grey", "brown", "chestnut", "blue", "lightblue", "green", "albino")
	switch(col)
		if("black")
			red = 0
			green = 0
			blue = 0
		if("grey")
			red = rand (100, 200)
			green = red
			blue = red
		if("brown")
			red = 102
			green = 51
			blue = 0
		if("chestnut")
			red = 153
			green = 102
			blue = 0
		if("blue")
			red = 51
			green = 102
			blue = 204
		if("lightblue")
			red = 102
			green = 204
			blue = 255
		if("green")
			red = 0
			green = 102
			blue = 0
		if("albino")
			red = rand (200, 255)
			green = rand (0, 150)
			blue = rand (0, 150)

	red = max(min(red + rand (-25, 25), 255), 0)
	green = max(min(green + rand (-25, 25), 255), 0)
	blue = max(min(blue + rand (-25, 25), 255), 0)

	skin_color = rgb( red, green, blue )

/datum/character/proc/update_preview_icon( var/datum/job/job, var/title )		//seriously. This is horrendous.
	var/icon/preview_icon = null

	var/g = "m"
	if(gender == FEMALE)	g = "f"

	var/icon/icobase
	var/datum/species/current_species = all_species[species]

	if(current_species)
		icobase = current_species.icobase
	else
		icobase = 'icons/mob/human_races/r_human.dmi'

	preview_icon = new /icon(icobase, "torso_[g]")
	preview_icon.Blend(new /icon(icobase, "groin_[g]"), ICON_OVERLAY)
	preview_icon.Blend(new /icon(icobase, "head_[g]"), ICON_OVERLAY)

	for(var/name in list("r_arm","r_hand","r_leg","r_foot","l_leg","l_foot","l_arm","l_hand"))
		if(organ_data[name] == "amputated") continue

		var/icon/temp = new /icon(icobase, "[name]")
		if(organ_data[name] == "cyborg")
			temp.MapColors(rgb(77,77,77), rgb(150,150,150), rgb(28,28,28), rgb(0,0,0))

		preview_icon.Blend(temp, ICON_OVERLAY)

	//Tail
	if(current_species && (current_species.tail))
		var/icon/temp = new/icon("icon" = current_species.effect_icons, "icon_state" = "[current_species.tail]_s")
		preview_icon.Blend(temp, ICON_OVERLAY)

	// Skin color
	if(current_species && (current_species.flags & HAS_SKIN_COLOR))
		preview_icon.Blend( skin_color, ICON_ADD )

	// Skin tone
	if(current_species && (current_species.flags & HAS_SKIN_TONE))
		if (skin_tone >= 0)
			preview_icon.Blend(rgb(skin_tone, skin_tone, skin_tone), ICON_ADD)
		else
			preview_icon.Blend(rgb(-skin_tone,  -skin_tone,  -skin_tone), ICON_SUBTRACT)

	var/icon/eyes_s = new/icon("icon" = 'icons/mob/human_face.dmi', "icon_state" = current_species ? current_species.eyes : "eyes_s")
	if ((current_species && (current_species.flags & HAS_EYE_COLOR)))
		eyes_s.Blend(eye_color, ICON_ADD)

	var/datum/sprite_accessory/h_style = hair_styles_list[hair_style]
	if(h_style)
		var/icon/hair_s = new/icon("icon" = h_style.icon, "icon_state" = "[h_style.icon_state]_s")
		hair_s.Blend( hair_color, ICON_ADD )
		eyes_s.Blend( hair_s, ICON_OVERLAY )

	var/datum/sprite_accessory/facial_h_style = facial_hair_styles_list[hair_face_style]
	if(facial_h_style)
		var/icon/facial_s = new/icon("icon" = facial_h_style.icon, "icon_state" = "[facial_h_style.icon_state]_s")
		facial_s.Blend(hair_face_color, ICON_ADD)
		eyes_s.Blend(facial_s, ICON_OVERLAY)

	var/icon/underwear_s = null
	if(underwear > 0 && underwear < 7 && current_species.flags & HAS_UNDERWEAR)
		underwear_s = new/icon("icon" = 'icons/mob/human.dmi', "icon_state" = "underwear[underwear]_[g]_s")

	var/icon/undershirt_s = null
	if(undershirt > 0 && undershirt < 5 && current_species.flags & HAS_UNDERWEAR)
		undershirt_s = new/icon("icon" = 'icons/mob/human.dmi', "icon_state" = "undershirt[undershirt]_s")

	var/icon/clothes_s = null

	if( job )
		clothes_s = job.make_preview_icon( backpack, title, g)

	if(disabilities & NEARSIGHTED)
		preview_icon.Blend(new /icon('icons/mob/eyes.dmi', "glasses"), ICON_OVERLAY)

	preview_icon.Blend(eyes_s, ICON_OVERLAY)
	if(underwear_s)
		preview_icon.Blend(underwear_s, ICON_OVERLAY)
	if(undershirt_s)
		preview_icon.Blend(undershirt_s, ICON_OVERLAY)
	if(clothes_s)
		preview_icon.Blend(clothes_s, ICON_OVERLAY)

	qdel(eyes_s)
	qdel(underwear_s)
	qdel(undershirt_s)
	qdel(clothes_s)

	return preview_icon

/datum/character/proc/setHairColor( var/r, var/g, var/b )
	hair_color = rgb( r, g, b )

/datum/character/proc/setFacialHairColor( var/r, var/g, var/b )
	hair_face_color = rgb( r, g, b )

/datum/character/proc/setSkinTone( var/r, var/g, var/b )
	skin_tone = rgb( r, g, b )

/datum/character/proc/setSkinColor( var/r, var/g, var/b )
	skin_color = rgb( r, g, b )

/datum/character/proc/setEyeColor( var/r, var/g, var/b )
	eye_color = rgb( r, g, b )

/datum/character/proc/enterMob()
	temporary = new_character // If we're a new character, then we're also temporary

	account.enterMob()
