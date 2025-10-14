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
		var currentSongTime = getRateAwareSongTime();

		for (note in playerStrumline.getNotesMayHit())
		{
			if (note == null || !note.alive || note.hasBeenHit || ignoreKinds.contains(note.kind))
				continue;

			if (currentSongTime >= note.strumTime)
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

        // Helpers keep autoplay timing aligned with playback-rate adjustments without double-applying pitch changes.
        private function getEffectivePlaybackRate():Float
        {
                var state = PlayState.instance;
                if (state != null && ReflectUtil.hasField(state, "playbackRate"))
                {
                        var stateRate = ReflectUtil.field(state, "playbackRate");
                        if (stateRate != null)
                        {
                                if (Std.isOfType(stateRate, Float))
                                {
                                        return stateRate;
                                }

                                var parsedStateRate = Std.parseFloat(Std.string(stateRate));
                                if (!Math.isNaN(parsedStateRate))
                                {
                                        return parsedStateRate;
                                }
                        }
                }

                var conductor = Conductor.instance;
                if (conductor != null && ReflectUtil.hasField(conductor, "playbackRate"))
                {
                        var conductorRate = ReflectUtil.field(conductor, "playbackRate");
                        if (conductorRate != null)
                        {
                                if (Std.isOfType(conductorRate, Float))
                                {
                                        return conductorRate;
                                }

                                var parsedConductorRate = Std.parseFloat(Std.string(conductorRate));
                                if (!Math.isNaN(parsedConductorRate))
                                {
                                        return parsedConductorRate;
                                }
                        }
                }

                if (FlxG.sound.music != null && ReflectUtil.hasField(FlxG.sound.music, "pitch"))
                {
                        var pitchValue = ReflectUtil.field(FlxG.sound.music, "pitch");
                        if (pitchValue != null)
                        {
                                if (Std.isOfType(pitchValue, Float))
                                {
                                        return pitchValue;
                                }

                                var parsedPitch = Std.parseFloat(Std.string(pitchValue));
                                if (!Math.isNaN(parsedPitch))
                                {
                                        return parsedPitch;
                                }
                        }
                }

                return 1.0;
        }

        private function getRateAwareSongTime():Float
        {
                var conductor = Conductor.instance;
                if (conductor == null)
                {
                        return 0;
                }

                var hasTimeWithDelta = ReflectUtil.hasField(conductor, "getTimeWithDelta");
                var songTime = hasTimeWithDelta ? conductor.getTimeWithDelta() : conductor.songPosition;

                var playbackRate = getEffectivePlaybackRate();
                if (Math.abs(playbackRate - 1.0) > 1e-6)
                {
                        var conductorHasRateField = ReflectUtil.hasField(conductor, "playbackRate")
                                || ReflectUtil.hasField(conductor, "rate")
                                || ReflectUtil.hasField(conductor, "timeScale");

                        if (!conductorHasRateField)
                        {
                                songTime *= playbackRate;
                        }
                }

                return songTime;
        }
}
