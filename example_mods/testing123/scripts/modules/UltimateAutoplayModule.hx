import flixel.FlxG;
import funkin.Conductor;
import funkin.Highscore;
import funkin.util.ReflectUtil;
import funkin.play.PlayState;
import funkin.play.scoring.Scoring;
import funkin.play.notes.NoteSprite;
import funkin.modding.module.Module;
import funkin.modding.events.ScriptEvent;
import funkin.modding.events.HitNoteScriptEvent;
import funkin.modding.events.SongLoadScriptEvent;
import funkin.util.Constants;

class UltimateAutoplayModule extends Module
{
	public static var ignoreKinds:Array<String> = ["Hurt Note", "Trap Note", "banNote1", "banNote2"];
	public static var isBotActive = false;

	var didit:Bool = false;

	public function new() {
		super("UltimateAutoplayModule");
		if (FlxG.save.data.BotMode == null)
			FlxG.save.data.BotMode = "off";
	}

	override function onSongLoaded(event:SongLoadScriptEvent)
	{
		super.onSongLoaded(event);
		UltimateAutoplayModule.isBotActive = (FlxG.save.data.BotMode != null && FlxG.save.data.BotMode != "off");
	}
	
	function onNoteHit(event)
	{
		if (UltimateAutoplayModule.isBotActive && event.note.noteData.getMustHitNote() && PlayState.instance != null) {
			if (event.hitDiff != 0) {
				PlayState.instance.playerStrumline.playStatic(event.note.noteData.getDirection());
				event.cancel();
			}
		}
	}

	function onNoteMiss(event)
	{
		if (UltimateAutoplayModule.isBotActive)
			event.cancel();
	}

	function onNoteGhostMiss(event)
	{
		if (UltimateAutoplayModule.isBotActive) event.cancel();
	}

	function onNoteHoldDrop(event)
	{
		if (UltimateAutoplayModule.isBotActive) event.cancel();
	}

	override function onUpdate(event:ScriptEvent):Void
	{
		super.onUpdate(event);
		onUpdatePause();

		var state = PlayState.instance;
		
		if (!UltimateAutoplayModule.isBotActive || state == null || state.isGamePaused || state.isBotPlayMode 
			|| state.playerStrumline == null || state.startingSong || state.isInCutscene)
		{
			return;
		}

		var playerStrumline = state.playerStrumline;
		var rateAwareSongTime = getRateAwareSongTime();

		for (note in playerStrumline.getNotesMayHit())
		{
			if (note == null || !note.alive || note.hasBeenHit || ignoreKinds.contains(note.kind))
				continue;

			if (rateAwareSongTime >= note.strumTime)
			{
				var perfectHitDiff = 0;
				var score = Scoring.scoreNote(perfectHitDiff);
				var daRating = Scoring.judgeNote(perfectHitDiff);
				var healthBonus = Constants.HEALTH_SICK_BONUS; 
				
				var hitEvent = new HitNoteScriptEvent(note, healthBonus, score, daRating, false, 0, perfectHitDiff, true);
				dispatchEvent(hitEvent);
				
				if (!hitEvent.eventCanceled)
				{
					Highscore.tallies.totalNotesHit++;
					Highscore.tallies.sickNotes++;
					playerStrumline.hitNote(note, true);
					playerStrumline.noteVibrations.tryNoteVibration();
					
					if (note.holdNoteSprite != null)
					{
						if (playerStrumline.isPlayer)
							playerStrumline.pressKey(note.holdNoteSprite.noteDirection);
						playerStrumline.playNoteHoldCover(note.holdNoteSprite);
					}
					
					if (hitEvent.doesNotesplash)
						playerStrumline.playNoteSplash(note.noteData.getDirection());
					
					state.vocals.playerVolume = 1;
					state.applyScore(hitEvent.score, hitEvent.judgement, hitEvent.healthChange, hitEvent.isComboBreak);
					state.popUpScore(hitEvent.judgement);
				}

				if (state.currentStage != null && state.currentStage.getPlayer() != null)
					state.currentStage.getPlayer().holdTimer = 0;
			}
		}

		for (holdNote in playerStrumline.holdNotes.members)
		{
			if (holdNote != null && holdNote.alive)
			{
				if (holdNote.hitNote && !holdNote.missedNote && holdNote.sustainLength > 0)
				{
					if (state.currentStage != null && state.currentStage.getPlayer() != null && state.currentStage.getPlayer().isSinging())
						state.currentStage.getPlayer().holdTimer = 0;
				}
				else if (holdNote.hitNote && holdNote.sustainLength <= 0)
				{
					playerStrumline.releaseKey(holdNote.noteDirection);
				}
			}
		}
	}

	public override function dispatchEvent(event:ScriptEvent):Void
	{
		if (!UltimateAutoplayModule.isBotActive || PlayState.instance == null) return;
		PlayState.instance.dispatchEvent(event);
	}

	// Helpers to adapt bot timing to playback rate while avoiding double application when the Conductor already handles it.
	inline function getEffectivePlaybackRate():Float
	{
		var state = PlayState.instance;
		if (state != null)
		{
			var stateRate = state.playbackRate;
			if (!Math.isNaN(stateRate) && stateRate > 0)
			{
				return stateRate;
			}
		}

		var conductor = Conductor.instance;
		if (conductor != null)
		{
			var conductorRateDynamic:Dynamic = ReflectUtil.getProperty(conductor, "playbackRate");
			if (conductorRateDynamic != null)
			{
				var conductorRate:Float = cast conductorRateDynamic;
				if (!Math.isNaN(conductorRate) && conductorRate > 0)
				{
					return conductorRate;
				}
			}
		}

		var music = FlxG.sound.music;
		if (music != null)
		{
			var pitch = music.pitch;
			if (!Math.isNaN(pitch) && pitch > 0)
			{
				return pitch;
			}
		}

		return 1.0;
	}

	inline function getRateAwareSongTime():Float
	{
		var conductor = Conductor.instance;
		if (conductor == null)
		{
			return 0;
		}

		var songTime = conductor.getTimeWithDelta();
		var music = FlxG.sound.music;
		if (music == null || !music.playing)
		{
			var rate = getEffectivePlaybackRate();
			if (!Math.isNaN(rate) && rate > 0 && rate != 1.0)
			{
				return songTime * rate;
			}
		}

		return songTime;
	}

	function onUpdatePause()
	{
		var substateClassName = ReflectUtil.getClassNameOf(FlxG.state.subState);
		if (substateClassName != 'funkin.play.PauseSubState')
		{
			didit = false;
			return;
		}
		var pauseState:Dynamic = FlxG.state.subState;
		if (!didit)
		{
			didit = true;
			pauseState.persistentUpdate = false;
			var menuEntries = pauseState.currentMenuEntries;
			var insertIndex = menuEntries.length > 2 ? menuEntries.length - 2 : menuEntries.length;
			menuEntries.insert(insertIndex, {
				text: "SuperBot: " + (FlxG.save.data.BotMode == null ? "off" : FlxG.save.data.BotMode),
				callback: () -> {
					var current = FlxG.save.data.BotMode;
					if (current == null || current == "off")
						FlxG.save.data.BotMode = "on";
					else
						FlxG.save.data.BotMode = "off";

					UltimateAutoplayModule.isBotActive = (FlxG.save.data.BotMode != "off");
					
					menuEntries[insertIndex].text = "SuperBot: " + FlxG.save.data.BotMode;
					FlxG.save.flush();
					pauseState.clearAndAddMenuEntries();
					pauseState.changeSelection();
				}
			});
			pauseState.clearAndAddMenuEntries();
			pauseState.changeSelection();
		}
	}
}
