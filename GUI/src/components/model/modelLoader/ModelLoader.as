/* Integra Live graphical user interface
 *
 * Copyright (C) 2009 Birmingham City University
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA   02110-1301,
 * USA.
 */


package components.model.modelLoader
{
	import com.mattism.http.xmlrpc.util.XMLRPCDataTypes;
	
	import flash.events.ErrorEvent;
	import flash.events.Event;
	import flash.events.EventDispatcher;
	import flash.events.TimerEvent;
	import flash.filesystem.File;
	import flash.geom.Rectangle;
	import flash.utils.Timer;
	
	import __AS3__.vec.Vector;
	
	import components.controller.IntegraController;
	import components.controller.events.LoadCompleteEvent;
	import components.controller.events.LoadFailedEvent;
	import components.model.Block;
	import components.model.Connection;
	import components.model.ControlPoint;
	import components.model.Envelope;
	import components.model.IntegraContainer;
	import components.model.IntegraDataObject;
	import components.model.IntegraModel;
	import components.model.MidiControlInput;
	import components.model.MidiRawInput;
	import components.model.ModuleInstance;
	import components.model.Player;
	import components.model.Scaler;
	import components.model.Scene;
	import components.model.Script;
	import components.model.Track;
	import components.model.userData.TrackUserData;
	import components.model.interfaceDefinitions.ControlInfo;
	import components.model.interfaceDefinitions.EndpointDefinition;
	import components.model.interfaceDefinitions.InterfaceDefinition;
	import components.model.interfaceDefinitions.StateInfo;
	import components.model.interfaceDefinitions.StateLabel;
	import components.model.interfaceDefinitions.StreamInfo;
	import components.model.interfaceDefinitions.ValueRange;
	import components.model.interfaceDefinitions.WidgetDefinition;
	import components.model.preferences.AudioSettings;
	import components.model.preferences.MidiSettings;
	import components.utils.IntegraConnection;
	import components.utils.Trace;
	
	import flexunit.framework.Assert;
	
	public class ModelLoader
	{
		public function ModelLoader( completionDispatcher:EventDispatcher )
		{
			_completionDispatcher = completionDispatcher; 
			_model = IntegraModel.singleInstance;
			
			_timeoutTimer.addEventListener( TimerEvent.TIMER_COMPLETE, onTimeout )
		}
		
		
		public function set serverUrl( serverUrl:String ):void
		{
			_serverUrl = serverUrl;
			
			LegacyMidiHandler.instance.serverUrl = _serverUrl;
		}
		

		public function loadModel():void
		{
			if( !_serverUrl )
			{
				Trace.error( "can't load model - no server url provided!" );
				return;
			}
			
			_mode = LOADING_ALL;
			_loadPhase = ModelLoadPhase.INTERFACE_LIST;
			_shouldAddDefaultNewProjectObjects = false;
			_error = null;
			_topLevelLoadedObjectPaths = new Vector.<Array>;
			_loadHierarchyLevel = 1;
			LegacyMidiHandler.instance.clear();
			
			_timeoutTimer.start();
			
			//load the list of available interfaces
			Assert.assertNull( _interfaceListCall );
			_interfaceListCall = new IntegraConnection( _serverUrl );
			_interfaceListCall.addEventListener( Event.COMPLETE, interfaceListHandler, false, 1 );
			_interfaceListCall.addEventListener( Event.COMPLETE, callResultHandler );
			_interfaceListCall.addEventListener( ErrorEvent.ERROR, rpcErrorHandler );
			_interfaceListCall.call( "query.interfacelist" );
		}


		public function loadBranchOfNodeTree( branchPath:Array, mode:String, presuppliedID:int, newEmbeddedModuleGuids:Array ):void
		{
			_branchPath = branchPath;
			_mode = mode;
			_presuppliedID = presuppliedID;

			_shouldAddDefaultNewProjectObjects = false;
			_error = null;
			_topLevelLoadedObjectPaths = new Vector.<Array>;
			_loadHierarchyLevel = branchPath.length + 1;
			LegacyMidiHandler.instance.clear();

			var interfacesToLoad:Vector.<String> = new Vector.<String>;
			for each( var guid:String in newEmbeddedModuleGuids )
			{
				Assert.assertFalse( _model.getInterfaceDefinitionByModuleGuid( guid ) );
				
				interfacesToLoad.push( guid );
				_model.interfaceList.push( guid );
			}
			
			loadInterfaceDefinitions( interfacesToLoad );
		}
		
		
		public function loadNewlyInstalledInterfaceDefinitions( newModuleGuids:Array ):void
		{
			_mode = LOADING_NEW_INTERFACES;
			
			_shouldAddDefaultNewProjectObjects = false;
			_error = null;
			
			var interfacesToLoad:Vector.<String> = new Vector.<String>;
			for each( var guid:String in newModuleGuids )
			{
				Assert.assertFalse( _model.getInterfaceDefinitionByModuleGuid( guid ) );
				
				interfacesToLoad.push( guid );
				_model.interfaceList.push( guid );
			}
			
			loadInterfaceDefinitions( interfacesToLoad );
		}		
		
		
		private function loadInterfaceDefinitions( interfacesToLoad:Vector.<String> = null ):void
		{
			_loadPhase = ModelLoadPhase.INTERFACE_DEFINITIONS;
			
			var methodCalls:Array = new Array;
			
			if( !interfacesToLoad ) interfacesToLoad = _model.interfaceList;
			
			for each( var guid:String in interfacesToLoad )
			{
				var interfaceInfoCall:Object = new Object;
				interfaceInfoCall.methodName = "query.interfaceinfo";
				interfaceInfoCall.params = [ guid ];
				methodCalls.push( interfaceInfoCall ); 

				var endpointsCall:Object = new Object;
				endpointsCall.methodName = "query.endpoints";
				endpointsCall.params = [ guid ];
				methodCalls.push( endpointsCall ); 

				var widgetsCall:Object = new Object;
				widgetsCall.methodName = "query.widgets";
				widgetsCall.params = [ guid ];
				methodCalls.push( widgetsCall ); 
			}
			
			var interfaceDefinitionsCall:IntegraConnection = new IntegraConnection( _serverUrl );
			interfaceDefinitionsCall.addEventListener( Event.COMPLETE, interfaceDefinitionsHandler, false, 1 );
			interfaceDefinitionsCall.addEventListener( Event.COMPLETE, callResultHandler );
			interfaceDefinitionsCall.addEventListener( ErrorEvent.ERROR, rpcErrorHandler );
			interfaceDefinitionsCall.addArrayParam( methodCalls );
			interfaceDefinitionsCall.callQueued( "system.multicall" );			
		}

		
		private function loadInstances():void
		{
			_loadPhase = ModelLoadPhase.INSTANCES;

			if( _mode == LOADING_ALL )
			{
				_model.clearInstances();
			}
			
			var instancesCall:IntegraConnection = new IntegraConnection( _serverUrl );
			instancesCall.addEventListener( Event.COMPLETE, instancesHandler, false, 1 );
			instancesCall.addEventListener( Event.COMPLETE, callResultHandler );
			instancesCall.addEventListener( ErrorEvent.ERROR, rpcErrorHandler );
			
			switch( _mode )
			{
				case LOADING_ALL:
					instancesCall.addArrayParam( [] );
					break;
				
				case IMPORTING_TRACK:
				case IMPORTING_BLOCK:
				case IMPORTING_MODULE:
					instancesCall.addArrayParam( _branchPath );
					break;
				
				case LOADING_NEW_INTERFACES:
				default:
					Assert.assertTrue( false );
					break;
			}
			
			instancesCall.call( "query.nodelist" );
		}
		
		
		private function loadStates():void
		{
			_loadPhase = ModelLoadPhase.STATES;
			
			var methodCalls:Array = new Array;
			
			loadObjectState( _model.project, methodCalls );  
			loadObjectState( _model.project.player, methodCalls );
			
			if( _mode == LOADING_ALL )
			{
				loadObjectState( _model.audioSettings, methodCalls );
				loadObjectState( _model.midiSettings, methodCalls );
			}

			for each( var track:Track in _model.project.tracks )
			{
				loadObjectState( track, methodCalls );
				
				for each( var block:Block in track.blocks )
				{
					loadObjectState( block, methodCalls );  
					
					for each( var module:ModuleInstance in block.modules )
					{
						loadObjectState( module, methodCalls );  
					}
					
					for each( var connection:Connection in block.connections )
					{
						loadObjectState( connection, methodCalls );
					}

					for each( var scaler:Scaler in block.scalers )
					{
						loadObjectState( scaler, methodCalls );  
					}

					for each( var midiControlInput:MidiControlInput in block.midiControlInputs )
					{
						loadObjectState( midiControlInput, methodCalls );  
					}

					for each( var envelope:Envelope in block.envelopes )
					{
						loadObjectState( envelope, methodCalls );

						for each( var controlPoint:ControlPoint in envelope.controlPoints )
						{
							loadObjectState( controlPoint, methodCalls );
						}
					}
					
					for each( var script:Script in block.scripts )
					{
						loadObjectState( script, methodCalls );  
					}
				}
				
				for each( var blockEnvelope:Envelope in track.blockEnvelopes )
				{
					loadObjectState( blockEnvelope, methodCalls );

					for each( controlPoint in blockEnvelope.controlPoints )
					{
						loadObjectState( controlPoint, methodCalls );
					}
				}
				
				for each( script in track.scripts )
				{
					loadObjectState( script, methodCalls );  
				}

				for each( connection in track.connections )
				{
					loadObjectState( connection, methodCalls );  
				}

				for each( scaler in track.scalers )
				{
					loadObjectState( scaler, methodCalls );  
				}
				
				for each( midiControlInput in track.midiControlInputs )
				{
					loadObjectState( midiControlInput, methodCalls );  
				}
			}
			
			for each( script in _model.project.scripts )
			{
				loadObjectState( script, methodCalls );  
			}

			for each( connection in _model.project.connections )
			{
				loadObjectState( connection, methodCalls );  
			}

			for each( scaler in _model.project.scalers )
			{
				loadObjectState( scaler, methodCalls );  
			}
			
			for each( midiControlInput in _model.project.midiControlInputs )
			{
				loadObjectState( midiControlInput, methodCalls );  
			}
			

			for each( var scene:Scene in _model.project.player.scenes )
			{
				loadObjectState( scene, methodCalls );  
			}

			var objectStatesCall:IntegraConnection = new IntegraConnection( _serverUrl );
			objectStatesCall.addEventListener( Event.COMPLETE, objectStatesHandler, false, 1 );
			objectStatesCall.addEventListener( Event.COMPLETE, callResultHandler );
			objectStatesCall.addEventListener( ErrorEvent.ERROR, rpcErrorHandler );
			objectStatesCall.addArrayParam( methodCalls ); 
			objectStatesCall.callQueued( "system.multicall" );
		}
		
		
		private function loadObjectState( object:IntegraDataObject, methodCalls:Array ):void
		{
			Assert.assertNotNull( object );
			
			for each( var endpoint:EndpointDefinition in object.interfaceDefinition.endpoints )
			{
				if( !endpoint.isStateful )
				{
					continue;
				}
				
				var methodCall:Object = new Object;
				methodCall.methodName = "query.get";
				methodCall.params = [ _model.getPathArrayFromID( object.id ).concat( endpoint.name ) ];
				
				methodCalls.push( methodCall );
			}
		}
		
		
		private function loadComplete():void
		{
			_loadPhase = ModelLoadPhase.LOADED;
			
			_completionDispatcher.dispatchEvent( new LoadCompleteEvent( _shouldAddDefaultNewProjectObjects ) );
		}


		private function callResultHandler( event:Event ):void
		{
			Trace.progress( "call Result Handler phase ", _loadPhase );
			
			if( _error )
			{
				handleLoadError();
				return;
			}
			
 			if( _timeoutTimer.running )
			{
				_timeoutTimer.stop();
			}
			
			switch( _loadPhase )
			{
				case ModelLoadPhase.INTERFACE_LIST:
					loadInterfaceDefinitions();
					break;
				
				case ModelLoadPhase.INTERFACE_DEFINITIONS:
					if( _mode == LOADING_NEW_INTERFACES )
					{
						loadComplete();
					}
					else
					{
						loadInstances();
					}
					break;

				case ModelLoadPhase.INSTANCES:
					loadStates();
					break;
					
				case ModelLoadPhase.STATES:
					resolveBlockEnvelopes();
					resolveScalerConnections( _model.project );
					removeInvalidChildSelection();
					LegacyMidiHandler.instance.translateToNewModules();
						
					loadComplete();
					break;
					
				case ModelLoadPhase.LOADED:
				default:
					Assert.assertTrue( false );
					break;
			}
			
			if( _error )
			{
				handleLoadError();
			}
		}


		private function rpcErrorHandler( event:ErrorEvent ):void
		{
			_error = "Something went wrong in the communication with the server!\n\nPlease try again";
			
			callResultHandler( event );
		}
		
		
		private function interfaceListHandler( event:Event ):void
		{
			var interfaceListArray:Object = event.target.getResponse().interfacelist;
			
			Assert.assertTrue( _model.interfaceList.length == 0 );
			Assert.assertNotNull( _interfaceListCall );
			_interfaceListCall = null;
			
			for each( var moduleId:String in interfaceListArray )
			{
				_model.interfaceList.push( moduleId );
			}
		}
		
		
		private function interfaceDefinitionsHandler( event:Event ):void
		{
			var multiResponse:Object = event.target.getResponse();
			
			for each( var response:Object in multiResponse )
			{
				var methodName:String = response[ 0 ].response;
				var moduleGuid:String = response[ 0 ].moduleid;
				
				switch( methodName )
				{
					case "query.interfaceinfo":
						var originGuid:String = response[ 0 ].originid;
						var moduleSource:String = response[ 0 ].modulesource;
						var implementationChecksum:uint = response[ 0 ].implementationchecksum;
						var interfaceInfo:Object = response[ 0 ].interfaceinfo;

						handleInterfaceInfo( moduleGuid, originGuid, moduleSource, implementationChecksum, interfaceInfo );
						break;

					case "query.endpoints":
						handleEndpoints( moduleGuid, response[ 0 ].endpoints );
						break;

					case "query.widgets":
						handleWidgets( moduleGuid, response[ 0 ].widgets );
						break;
					
					default:
						Assert.assertTrue( false );
						break;
				}				
			}			
		}
		
		
		private function handleInterfaceInfo( moduleGuid:String, originGuid:String, moduleSource:String, implementationChecksum:uint, info:Object ):void
		{
			var interfaceDefinition:InterfaceDefinition = new InterfaceDefinition;
			interfaceDefinition.moduleGuid = moduleGuid;
			interfaceDefinition.originGuid = originGuid;
			interfaceDefinition.moduleSource = moduleSource;
			interfaceDefinition.implementationChecksum = implementationChecksum;
			
			interfaceDefinition.interfaceInfo.name = info.name;
			interfaceDefinition.interfaceInfo.label = info.label;
			interfaceDefinition.interfaceInfo.description = info.description;
			
			for each( var tag:String in info.tags )
			{
				interfaceDefinition.interfaceInfo.tags.push( tag );
			}
			
			interfaceDefinition.interfaceInfo.author = info.author;
			interfaceDefinition.interfaceInfo.createdDate = parseDateTime( info.createddate );
			interfaceDefinition.interfaceInfo.modifiedDate = parseDateTime( info.modifieddate );
			
			_model.addInterfaceDefinition( interfaceDefinition );
		}

		
		private function handleEndpoints( moduleGuid:String, info:Object ):void
		{
			var interfaceDefinition:InterfaceDefinition = _model.getInterfaceDefinitionByModuleGuid( moduleGuid );
			Assert.assertNotNull( interfaceDefinition );

			for each( var endpointInfo:Object in info )
			{
				var endpoint:EndpointDefinition = new EndpointDefinition;
				endpoint.name = endpointInfo.name;
				endpoint.label = endpointInfo.label;
				endpoint.description = endpointInfo.description;
				
				if( endpointInfo.hasOwnProperty( "controlinfo" ) )
				{
					var serverControlInfo:Object = endpointInfo.controlinfo;
					var controlInfo:ControlInfo = new ControlInfo;
					
					switch( serverControlInfo.type )
					{
						case "state":
							controlInfo.type = ControlInfo.STATE;
							controlInfo.stateInfo = handleStateInfo( serverControlInfo.stateinfo );
							break;
						
						case "bang":
							controlInfo.type = ControlInfo.BANG;
							break;
							
						default:
							Trace.error( "unrecognisted control type", serverControlInfo.type );
							break;
					}
					
					controlInfo.canBeSource = ( serverControlInfo.canbesource > 0 );
					controlInfo.canBeTarget = ( serverControlInfo.canbetarget > 0 );
					controlInfo.isSentToHost = ( serverControlInfo.issenttohost > 0 );
					
					endpoint.controlInfo = controlInfo;
					
				}
				
				if( endpointInfo.hasOwnProperty( "streaminfo" ) )
				{
					var serverStreamInfo:Object = endpointInfo.streaminfo;
					var streamInfo:StreamInfo = new StreamInfo;
					
					switch( serverStreamInfo.type )
					{
						case "audio":
							streamInfo.streamType = StreamInfo.TYPE_AUDIO;
							break;
						
						default:
							Trace.error( "unrecognisted stream type", endpointInfo.streaminfo.type );
					}

					switch( serverStreamInfo.direction )
					{
						case "input":
							streamInfo.streamDirection = StreamInfo.DIRECTION_INPUT;
							break;
						
						case "output":
							streamInfo.streamDirection = StreamInfo.DIRECTION_OUTPUT;
							break;

						default:
							Trace.error( "unrecognisted stream direction", endpointInfo.streaminfo.direction );
					}
					
					endpoint.streamInfo = streamInfo;
				}
			
				
				interfaceDefinition.endpoints.push( endpoint );
			}
		}
		
		
		private function handleStateInfo( info:Object ):StateInfo
		{
			var stateInfo:StateInfo = new StateInfo;			
			
			switch( info.type )
			{
				case "string":
					stateInfo.valueType = StateInfo.STRING;
					break;

				case "integer":
					stateInfo.valueType = StateInfo.INTEGER;
					break;

				case "float":
					stateInfo.valueType = StateInfo.FLOAT;
					break;
				
				default:
					Trace.error( "unhandled state type", info.type );
					break;
			}

			if( info.constraint.hasOwnProperty( "range" ) )
			{
				var range:ValueRange = new ValueRange;
				
				range.minimum = info.constraint.range.minimum;
				range.maximum = info.constraint.range.maximum;
				
				stateInfo.constraint.range = range;				
			}

			if( info.constraint.hasOwnProperty( "allowedstates" ) )
			{
				var allowedValues:Vector.<Object> = new Vector.<Object>;
				
				for each( var allowedValue:Object in info.constraint.allowedstates )
				{
					allowedValues.push( allowedValue );					
				}
				
				stateInfo.constraint.allowedValues = allowedValues;				
			}
	
			stateInfo.defaultValue = info.defaultvalue;
			
			if( info.hasOwnProperty( "scale" ) )
			{
				stateInfo.scale.type = info.scale.type;
			}
			
			
			for each( var serverStateLabel:Object in info.statelabels )
			{
				var stateLabel:StateLabel = new StateLabel;
				stateLabel.label = serverStateLabel.text;
				stateLabel.value = serverStateLabel.value;
				
				stateInfo.stateLabels.push( stateLabel );
			}
			
			return stateInfo;
		}

		
		private function handleWidgets( moduleGuid:String, info:Object ):void
		{
			var interfaceDefinition:InterfaceDefinition = _model.getInterfaceDefinitionByModuleGuid( moduleGuid );
			Assert.assertNotNull( interfaceDefinition );
			
			for each( var widgetInfo:Object in info )
			{
				var widgetDefinition:WidgetDefinition = new WidgetDefinition;

				widgetDefinition.type = widgetInfo.type;
				widgetDefinition.label = widgetInfo.label;
				
				var position:Rectangle = new Rectangle;
				position.x = widgetInfo.position.x;
				position.y = widgetInfo.position.y;
				position.width = widgetInfo.position.width;
				position.height = widgetInfo.position.height;
				widgetDefinition.position = position;

				for each( var mappingInfo:Object in widgetInfo.mapping )
				{
					widgetDefinition.attributeToEndpointMap[ mappingInfo.widgetattribute ] = mappingInfo.endpoint; 	
				}
				
				interfaceDefinition.widgets.push( widgetDefinition );
			}
		}
		
		
		private function parseDateTime( dateTimeString:String ):Date
		{
			Assert.assertTrue( dateTimeString.length >= 19 );
			
			var year:uint = uint( dateTimeString.substr( 0, 4 ) );
			var month:uint = uint( dateTimeString.substr( 5, 2 ) );
			var day:uint = uint( dateTimeString.substr( 8, 2 ) );
			var hour:uint = uint( dateTimeString.substr( 11, 2 ) );
			var minute:uint = uint( dateTimeString.substr( 14, 2 ) );
			var second:uint = uint( dateTimeString.substr( 17, 2 ) );
			
			return new Date( year, month-1, day, hour, minute, second );
		}

		
		private function instancesHandler( event:Event ):void
		{
			var response:Object = event.target.getResponse();
			var nodeList:Array = response.nodelist as Array;
			Assert.assertNotNull( nodeList );

			var foundProject:Boolean = false;
			var foundProjectPlayer:Boolean = false;
			var foundProjectMidiMonitor:Boolean = false;
			var foundAudioSettings:Boolean = false;
			var foundMidiSettings:Boolean = false;
			
			var parent:IntegraDataObject = null;
			
			var blockEnvelopes:Vector.<Envelope> = new Vector.<Envelope>;
			
			//parse nodelist
			for each( var node:Object in nodeList )
			{
				var moduleGuid:String = node.guid;
				var interfaceDefinition:InterfaceDefinition = _model.getInterfaceDefinitionByModuleGuid( moduleGuid );
				if( !interfaceDefinition )
				{
					Trace.error( "Can't resolve class guid", moduleGuid );
					continue;
				}
				
				var interfaceName:String = interfaceDefinition.interfaceInfo.name;

				var path:Array = node.path;
				var hierarchyLevel:uint = path.length;

				Assert.assertTrue( hierarchyLevel >= 1 );

				if( LegacyMidiHandler.instance.isLegacyMidiModule( interfaceDefinition ) )
				{
					Trace.progress( "Encoutered legacy \"MIDI\" module: ", path );
					LegacyMidiHandler.instance.storeLegacyMidiModulePath( path );
					continue;
				}
				
				if( ( _mode != LOADING_ALL ) && _model.getIDFromPathArray( path ) >= 0 )
				{
					continue;	//we already have this node!
				}
				
				if( hierarchyLevel <= _loadHierarchyLevel )
				{
					Assert.assertTrue( hierarchyLevel == _loadHierarchyLevel );
					_topLevelLoadedObjectPaths.push( path );	
				}
				
				var parentID:int = -1;
				if( hierarchyLevel > 1 )
				{
					parentID = _model.getIDFromPathArray( path.slice( 0, path.length - 1 ) );
					if( parentID < 0 )
					{
						foundExtraneousNode( path, interfaceDefinition, "can't resolve path" );
						continue;
					}
				}
				
				var name:String = path[ path.length - 1 ];
				
				if( hierarchyLevel != 4 )
				{
					if( interfaceDefinition.hasAudioEndpoints || !interfaceDefinition.isCore )
					{
						//this gui only expects non-core or audio nodes at level 4
						foundExtraneousNode( path, interfaceDefinition, "non-core or audio node at wrong hierarchy level" );
						continue;						
					}
				}
				
					
				switch( path.length )
				{
					case 1:
						//this gui only expects to find one container, which it interprets as the project, and
						//audio/midi settings objects at level 1
						switch( interfaceName )
						{
							case IntegraContainer._serverInterfaceName:
								if( foundProject )
								{
									foundExtraneousNode( path, interfaceDefinition, "more than one top-level project container" );
								}
								else
								{
									foundProject = true;
									_model.project.name = name;
								}
								break;
								
							case AudioSettings._serverInterfaceName:
								if( foundAudioSettings )
								{
									foundExtraneousNode( path, interfaceDefinition, "more than one AudioSettings" );
								}
								else
								{
									foundAudioSettings = true;
									_model.audioSettings.name = name;
								}
								break;
							
							case MidiSettings._serverInterfaceName:
								if( foundMidiSettings )
								{
									foundExtraneousNode( path, interfaceDefinition, "more than one MidiSettings" );
								}
								else
								{
									foundMidiSettings = true;
									_model.midiSettings.name = name;
								}
								break;							

							default:
								foundExtraneousNode( path, interfaceDefinition, "unexpected class in hierarchy level 1" );
								break;
						}
						
						break;
						
					case 2:
						//this gui only expects to find containers, scripts, connections, scalers, midi control inputs, one player and one midi at level 2, 
						//which it interprets as tracks, project-level scripts and connections, and the project player respectively
						//they are all expected to have the project as their parent.
						if( path[ 0 ] != _model.project.name )
						{
							foundExtraneousNode( path, interfaceDefinition, "wrong parent" );	//wrong parent
							break;
						}

						switch( interfaceName )
						{
							case IntegraContainer._serverInterfaceName:
								var track:Track = new Track();
								giveNewID( track );
								track.name = name;
								_model.addDataObject( parentID, track );
								break;
								
							case Script._serverInterfaceName:
								var script:Script = new Script();
								giveNewID( script );
								script.name = name;
								_model.addDataObject( parentID, script );
								break;

							case Connection._serverInterfaceName:
								var connection:Connection = new Connection();
								giveNewID( connection );
								connection.name = name;
								_model.addDataObject( parentID, connection );
								break;
							
							case Scaler._serverInterfaceName:
								var scaler:Scaler = new Scaler();
								giveNewID( scaler );
								scaler.name = name;
								_model.addDataObject( parentID, scaler );
								break;

							case MidiControlInput._serverInterfaceName:
								var midiControlInput:MidiControlInput = new MidiControlInput();
								giveNewID( midiControlInput );
								midiControlInput.name = name;
								_model.addDataObject( parentID, midiControlInput );
								break;
							
							case Player._serverInterfaceName:
								if( foundProjectPlayer )
								{
									foundExtraneousNode( path, interfaceDefinition, "more than one player" );
								}
								else
								{
									foundProjectPlayer = true;
									_model.project.player.name = name;
								}
								break;
							
							case MidiRawInput._serverInterfaceName:
								if( foundProjectMidiMonitor )
								{
									foundExtraneousNode( path, interfaceDefinition, "more than one project midi monitor" );
								}
								else
								{
									foundProjectMidiMonitor = true;
									_model.project.midiMonitor.name = name;
									_model.project.midiMonitor.interfaceDefinition = interfaceDefinition;
								}
								break;
							
							default:
								foundExtraneousNode( path, interfaceDefinition, "unexpected class in hierarchy level 2" );
								break;
						}
						break;
						
					case 3:
						//this gui only expects to find containers, envelopes, connections, scalers, midi control inputs, scripts, midi and scenes at level 3, 
						//it interprets these as blocks, block envelopes, track-level connections scripts, and scenes (under the player)
						//they are expected to have an existing track as their parent.
						parent = _model.getDataObjectByID( parentID );
						if( !parent is Track && !(interfaceName == "Scene" && parent is Player ) )
						{
							foundExtraneousNode( path, interfaceDefinition, "wrong parent type" );		//wrong parent type
							break;
						}
						
						switch( interfaceName )
						{
							case IntegraContainer._serverInterfaceName:	
								var block:Block = new Block();
								giveNewID( block );
								block.name = name;
								_model.addDataObject( parentID, block );
								break;
								
							case Envelope._serverInterfaceName:
								var blockEnvelope:Envelope = new Envelope();
								giveNewID( blockEnvelope );
								blockEnvelope.name = name;
								_model.addDataObject( parentID, blockEnvelope );
								break;

							case Script._serverInterfaceName:
								script = new Script();
								giveNewID( script );
								script.name = name;
								_model.addDataObject( parentID, script );
								break;
								
							case Connection._serverInterfaceName:
								connection = new Connection();
								giveNewID( connection );
								connection.name = name;
								_model.addDataObject( parentID, connection );
								break;						

							case Scaler._serverInterfaceName:
								scaler = new Scaler();
								giveNewID( scaler );
								scaler.name = name;
								_model.addDataObject( parentID, scaler );
								break;

							case MidiControlInput._serverInterfaceName:
								midiControlInput = new MidiControlInput();
								giveNewID( midiControlInput );
								midiControlInput.name = name;
								_model.addDataObject( parentID, midiControlInput );
								break;
							
							case Scene._serverInterfaceName:
								var scene:Scene = new Scene();
								giveNewID( scene );
								scene.name = name;
								_model.addDataObject( parentID, scene );
								break;						

							default:
								foundExtraneousNode( path, interfaceDefinition, "unexpected class in hierarchy level 3" );
								break;
						}
																			
						break;
						
					case 4:
						//this gui only expects to find audio modules, connections, scalers, midi control inputs, scripts, envelopes and control points for block envelopes at level 4
						parent = _model.getDataObjectByID( parentID );
						if( !parent is Block && !(interfaceName == "ControlPoint" && parent is Envelope ) )
						{
							foundExtraneousNode( path, interfaceDefinition, "wrong parent type" );		//wrong parent type
							break;
						}
						
						switch( interfaceName )
						{
							case Connection._serverInterfaceName:
								connection = new Connection();
								giveNewID( connection );
								connection.name = name;
								_model.addDataObject( parentID, connection );
								break;						

							case Scaler._serverInterfaceName:
								scaler = new Scaler();
								giveNewID( scaler );
								scaler.name = name;
								_model.addDataObject( parentID, scaler );
								break;
							
							case MidiControlInput._serverInterfaceName:
								midiControlInput = new MidiControlInput();
								giveNewID( midiControlInput );
								midiControlInput.name = name;
								_model.addDataObject( parentID, midiControlInput );
								break;

							case Envelope._serverInterfaceName:
								var envelope:Envelope = new Envelope();
								giveNewID( envelope );
								envelope.name = name;
								_model.addDataObject( parentID, envelope );
								break;						
							
							case ControlPoint._serverInterfaceName:
								var controlPoint:ControlPoint = new ControlPoint();
								giveNewID( controlPoint );
								controlPoint.name = name;
								_model.addDataObject( parentID, controlPoint );
								break;
								
							case Script._serverInterfaceName:
								script = new Script();
								giveNewID( script );
								script.name = name;
								_model.addDataObject( parentID, script );
								break;	

							default:
								var moduleInstance:ModuleInstance = new ModuleInstance;
								giveNewID( moduleInstance );
								moduleInstance.name = name;
								moduleInstance.interfaceDefinition = interfaceDefinition;
								moduleInstance.attributes = new Object;
								
								_model.addDataObject( parentID, moduleInstance );
								break;	
						}
						
						break;
						
					case 5:
						//this gui only expects to find control points at level 5
						//they are all expected to have envelopes as their parent
						if( !_model.getEnvelope( parentID ) )
						{
							foundExtraneousNode( path, interfaceDefinition, "in hierarchy level 5 all objects should have envelopes as their parent" );
							break;
						}

						switch( interfaceName )
						{
							case ControlPoint._serverInterfaceName:
								controlPoint = new ControlPoint();
								giveNewID( controlPoint );
								controlPoint.name = name;
								_model.addDataObject( parentID, controlPoint );
								break;						
							
							default:
								foundExtraneousNode( path, interfaceDefinition, "in hierarchy level 5 all objects should be control points" );
								break;
						}
						
						break;

					default:
						//this gui only expects to find objects at levels 1, 2, 3, 4 and 5
						foundExtraneousNode( path, interfaceDefinition, "this gui only expects to find objects at levels 1, 2, 3, 4 and 5" );
						break;
				}
			}

			if( _error ) 
			{
				 return;
			}
			
			if( _mode != LOADING_ALL )
			{
				return;
			}

			if( !foundProject )
			{
				var createProjectCall:IntegraConnection = new IntegraConnection( _serverUrl );
				createProjectCall.addEventListener( ErrorEvent.ERROR, rpcErrorHandler );
				createProjectCall.addParam( _model.getCoreInterfaceGuid( IntegraContainer._serverInterfaceName ), XMLRPCDataTypes.STRING );
				createProjectCall.addParam( _model.project.name, XMLRPCDataTypes.STRING );
				createProjectCall.addArrayParam( new Array );
				createProjectCall.callQueued( "command.new" );
				
				_shouldAddDefaultNewProjectObjects = true;
			}		
			
			if( !foundProjectPlayer )
			{
				var createProjectPlayerCall:IntegraConnection = new IntegraConnection( _serverUrl );
				createProjectPlayerCall.addEventListener( ErrorEvent.ERROR, rpcErrorHandler );
				createProjectPlayerCall.addParam( _model.getCoreInterfaceGuid( Player._serverInterfaceName ), XMLRPCDataTypes.STRING );
				createProjectPlayerCall.addParam( _model.project.player.name, XMLRPCDataTypes.STRING );
				createProjectPlayerCall.addArrayParam( _model.getPathArrayFromID( _model.project.id ) );
				createProjectPlayerCall.callQueued( "command.new" );
			}

			if( !foundProjectMidiMonitor )
			{
				var createProjectMidiMonitorCall:IntegraConnection = new IntegraConnection( _serverUrl );
				createProjectMidiMonitorCall.addEventListener( ErrorEvent.ERROR, rpcErrorHandler );
				createProjectMidiMonitorCall.addParam( _model.getCoreInterfaceGuid( MidiRawInput._serverInterfaceName ), XMLRPCDataTypes.STRING );
				createProjectMidiMonitorCall.addParam( _model.project.midiMonitor.name, XMLRPCDataTypes.STRING );
				createProjectMidiMonitorCall.addArrayParam( _model.getPathArrayFromID( _model.project.id ) );
				createProjectMidiMonitorCall.callQueued( "command.new" );
			}
			
			//the audio/midi settings objects are expected to be both present, or both not present
			if( foundAudioSettings != foundMidiSettings )
			{
				Trace.error("device settings not configured as expected" );
				Assert.assertTrue( false );
			}
			
			if( !foundAudioSettings )
			{
				createPreferencesObjects();
			}
		}	
		
		
		private function createPreferencesObjects():void
		{
			var audioSettingsLocalFile:File = AudioSettings.localFile;
			if( audioSettingsLocalFile.exists )
			{
				var loadAudioSettingsCall:IntegraConnection = new IntegraConnection( _serverUrl );
				loadAudioSettingsCall.addEventListener( ErrorEvent.ERROR, rpcErrorHandler );
				loadAudioSettingsCall.addParam( audioSettingsLocalFile.nativePath, XMLRPCDataTypes.STRING );
				loadAudioSettingsCall.addArrayParam( new Array() );		//load into root level
				loadAudioSettingsCall.callQueued( "command.load" );
			}
			else
			{
				var newAudioSettingsCall:IntegraConnection = new IntegraConnection( _serverUrl );
				newAudioSettingsCall.addEventListener( ErrorEvent.ERROR, rpcErrorHandler );
				newAudioSettingsCall.addParam( _model.getCoreInterfaceGuid( AudioSettings._serverInterfaceName ), XMLRPCDataTypes.STRING );
				newAudioSettingsCall.addParam( _model.audioSettings.name, XMLRPCDataTypes.STRING );
				newAudioSettingsCall.addArrayParam( new Array );
				newAudioSettingsCall.callQueued( "command.new" );
			}

			var midiSettingsLocalFile:File = MidiSettings.localFile;
			if( midiSettingsLocalFile.exists )
			{
				var loadMidiSettingsCall:IntegraConnection = new IntegraConnection( _serverUrl );
				loadMidiSettingsCall.addEventListener( ErrorEvent.ERROR, rpcErrorHandler );
				loadMidiSettingsCall.addParam( midiSettingsLocalFile.nativePath, XMLRPCDataTypes.STRING );
				loadMidiSettingsCall.addArrayParam( new Array() );		//load into root level
				loadMidiSettingsCall.callQueued( "command.load" );
			}
			else
			{
				var newMidiSettingsCall:IntegraConnection = new IntegraConnection( _serverUrl );
				newMidiSettingsCall.addEventListener( ErrorEvent.ERROR, rpcErrorHandler );
				newMidiSettingsCall.addParam( _model.getCoreInterfaceGuid( MidiSettings._serverInterfaceName ), XMLRPCDataTypes.STRING );
				newMidiSettingsCall.addParam( _model.midiSettings.name, XMLRPCDataTypes.STRING );
				newMidiSettingsCall.addArrayParam( new Array );
				newMidiSettingsCall.callQueued( "command.new" );
			}
		}
		
		
		private function foundExtraneousNode( path:Array, interfaceDefinition:InterfaceDefinition, comment:String, shouldPreventLoad:Boolean = true ):void
		{
			Trace.error( "Found extraneous node.  Path = " + path.join( "." ) + ", classname = " + interfaceDefinition.interfaceInfo.name + ", comment = " + comment );

			if( !shouldPreventLoad )
			{
				return;
			}
			
			switch( _mode )
			{
				case LOADING_ALL:
					_error = "This file cannot be opened as a project.\n\nTry importing it as a track, block or module";
					break;
				
				case IMPORTING_TRACK:
					_error = "This file cannot be imported as a track.\n\nTry opening it as a project, or importing it as a block or module";
					break;
				
				case IMPORTING_BLOCK:
					_error = "This file cannot be imported as a block.\n\nTry opening it as a project, or importing it as a track or module";
					break;
				
				case IMPORTING_MODULE:
					_error = "This file cannot be imported as a module.\n\nTry opening it as a project, or importing it as a track or block";
					break;
				
				case LOADING_NEW_INTERFACES:
				default:
					Assert.assertFalse( true );
					break;
			}
		}
		
		private function foundInvalidSelectedChild( containerType:String ):void
		{
			Trace.error( "Found selectedChild in userData with no corresponding ", containerType );
		}
		
		private function objectStatesHandler( event:Event ):void
		{
			var responses:Object = event.target.getResponse();
			
			for each( var response:Object in responses )
			{
				var responseData:Object = response[ 0 ];
			
				handleAttributeValue( responseData );	
			}
		}

		
		private function handleAttributeValue( responseData:Object ):void
		{
			var path:Array = responseData.path;
			Assert.assertTrue( path.length >= 2 );

			var objectPath:Array = path.slice( 0, path.length - 1 );
			var attributeName:String = path[ path.length - 1 ];
			
			var objectID:int = _model.getIDFromPathArray( objectPath );
			Assert.assertTrue( objectID >= 0 );
			
			var dataObject:IntegraDataObject = _model.getDataObjectByID( objectID );
			Assert.assertNotNull( dataObject );
			
			var value:Object = responseData.value;
			if( value == null )
			{
				return;
			}
			
			if( !dataObject.setAttributeFromServer( attributeName, value, _model ) )
			{
				//failed to store this attribute value
				Assert.assertTrue( false );
			}
		}
		
		
		private function onTimeout( event:TimerEvent ):void
		{
			_interfaceListCall.removeEventListener( Event.COMPLETE, interfaceListHandler );
			_interfaceListCall.removeEventListener( Event.COMPLETE, callResultHandler );
			_interfaceListCall.removeEventListener( ErrorEvent.ERROR, rpcErrorHandler );
			_interfaceListCall = null;
			
			_timeoutTimer.stop();
			
			loadModel();
		}


		private function resolveBlockEnvelopes():void
		{
			if( _mode == IMPORTING_BLOCK || _mode == IMPORTING_MODULE )
			{
				return;	
			}
			
			for each( var track:Track in _model.project.tracks )
			{
				var blockIDsWithMatchedEnvelopes:Object = new Object;
				
				for each( var envelope:Envelope in track.blockEnvelopes )
				{
					var envelopeTarget:Connection = _model.getEnvelopeTarget( envelope.id );
					if( !envelopeTarget )
					{
						foundExtraneousBlockEnvelope( envelope );	//not set up like a proper block envelope 
						continue;
					}
					
					var controlPoints:Vector.<ControlPoint> = envelope.orderedControlPoints;
					if( envelopeTarget.targetAttributeName != "active" || controlPoints.length != 4 || 
							controlPoints[ 0 ].tick != -1 || controlPoints[ 0 ].value != 0 || 
							controlPoints[ 1 ].tick != 0 || controlPoints[ 1 ].value != 1 ||
							controlPoints[ 2 ].tick < 1 || controlPoints[ 2 ].value != 1 ||
							controlPoints[ 3 ].tick < 2 || controlPoints[ 3 ].value != 0 )
					{
						foundExtraneousBlockEnvelope( envelope );	//not set up like a proper block envelope 
						continue;
					}
					
					var block:Block = _model.getBlock( envelopeTarget.targetObjectID );
					if( !block || blockIDsWithMatchedEnvelopes.hasOwnProperty( block.id ) || block.parentID != track.id )
					{
						foundExtraneousBlockEnvelope( envelope );	//can't find block, or block already is matched with an envelope, or block is in wrong track
						continue;
					}
					
					block.blockEnvelope = envelope;
					blockIDsWithMatchedEnvelopes[ block.id ] = 1;
				}

				for each( block in track.blocks )
				{
					if( !blockIDsWithMatchedEnvelopes.hasOwnProperty( block.id ) )
					{
						foundBlockWithoutEnvelope( block );
					}
				}
			}
		}

		
		private function resolveScalerConnections( container:IntegraContainer ):void
		{
			for each( var connection:Connection in container.connections )
			{
				var sourceObject:IntegraDataObject = null;
				if( connection.sourceObjectID >= 0 ) 
				{
					if( _model.doesObjectExist( connection.sourceObjectID ) )
					{
						sourceObject = _model.getDataObjectByID( connection.sourceObjectID );
						if( sourceObject && sourceObject is Scaler )
						{
							var scaler:Scaler = sourceObject as Scaler;
							
							if( connection.sourceAttributeName == "outValue" )
							{
								scaler.downstreamConnection = connection;
							}
						}
					}
				}
				
				var targetObject:IntegraDataObject = null;
				if( connection.targetObjectID >= 0 ) 
				{
					if( _model.doesObjectExist( connection.targetObjectID ) )
					{
						targetObject = _model.getDataObjectByID( connection.targetObjectID );
						if( targetObject is Scaler )
						{
							scaler = targetObject as Scaler;
							
							if( connection.targetAttributeName == "inValue" )
							{
								scaler.upstreamConnection = connection;
								
								// midi input control crossreferences
								if( sourceObject && sourceObject is MidiControlInput )
								{
									var midiControlInput:MidiControlInput = sourceObject as MidiControlInput;
									scaler.midiControlInput = midiControlInput;
									midiControlInput.scaler = scaler;
								}
							}
						}
					}
				}
			}
			
			//check that each scaler has connections
			for each( scaler in container.scalers )
			{
				if( scaler.upstreamConnection == null || scaler.downstreamConnection == null )
				{
					foundScalerWithoutConnections( scaler );	
				}
			}
			
			//walk tree
			for each( var child:IntegraDataObject in container.children )
			{
				if( child is IntegraContainer )
				{
					resolveScalerConnections( child as IntegraContainer );
				}
			}
		}		
		
		// This function works around a bug in <=1.6 where the selectedChild field in userData is not removed when blocks are moved between tracks -jb
		private function removeInvalidChildSelection():void
		{
			if( _mode == IMPORTING_BLOCK || _mode == IMPORTING_MODULE )
			{
				return;	
			}
			
			for each( var track:Track in _model.project.tracks )
			{				
				var trackUserData:TrackUserData = track.trackUserData;
								
				for ( var selectedItem:String in trackUserData.selectedChildIDs )
				{
					if ( selectedItem == "-1" )
					{
						foundInvalidSelectedChild( "Block" );
						trackUserData.setChildSelected( -1, false );
					}
				}  
			}
		}
		
		private function foundExtraneousBlockEnvelope( envelope:Envelope ):void
		{
			foundExtraneousNode( _model.getPathArrayFromID( envelope.id ), envelope.interfaceDefinition, "foundExtraneousBlockEnvelope" );
			removeObjectAndChildrenAndReferringConnections( envelope.id );	
		}


		private function foundBlockWithoutEnvelope( block:Block ):void
		{
			foundExtraneousNode( _model.getPathArrayFromID( block.id ), block.interfaceDefinition, "foundBlockWithoutEnvelope" );
			removeObjectAndChildrenAndReferringConnections( block.id );	
		}

		
		private function foundScalerWithoutConnections( scaler:Scaler ):void
		{
			foundExtraneousNode( _model.getPathArrayFromID( scaler.id ), scaler.interfaceDefinition, "foundScalerWithoutConnections", false );
			
			if( scaler.upstreamConnection ) _model.removeDataObject( scaler.upstreamConnection.id );
			if( scaler.downstreamConnection ) _model.removeDataObject( scaler.downstreamConnection.id );

			_model.removeDataObject( scaler.id );	
		}

		
		private function removeObjectAndChildrenAndReferringConnections( objectID:int ):void
		{
			var object:IntegraDataObject = _model.getDataObjectByID( objectID );
			Assert.assertNotNull( object );
				
			var childIDs:Vector.<int> = new Vector.<int>;
			
			if( object is IntegraContainer )
			{
				for each( var child:IntegraDataObject in ( object as IntegraContainer ).children )
				{
					childIDs.push( child.id );
				} 
			}
			
			if( object is Envelope )
			{
				for each( var controlPoint:ControlPoint in ( object as Envelope ).controlPoints )
				{
					childIDs.push( controlPoint.id );
				}	
			}
			
			for( var container:IntegraContainer = _model.getParent( objectID ) as IntegraContainer; container; container = _model.getParent( container.id ) as IntegraContainer )
			{
				for each( var connection:Connection in container.connections )
				{
					if( connection.sourceObjectID == objectID || connection.targetObjectID == objectID )
					{
						_model.removeDataObject( connection.id ); 
					}
				}
			}
			
			for each( var childID:int in childIDs )
			{
				if( _model.doesObjectExist( childID ) )
				{
					removeObjectAndChildrenAndReferringConnections( childID );
				}
			}	
			
			_model.removeDataObject( objectID );
		}
		
		
		private function giveNewID( object:IntegraDataObject ):void
		{
			var importedObjectType:Class = null;
			switch( _mode )
			{
				case IMPORTING_TRACK:
				case IMPORTING_BLOCK:
					importedObjectType = IntegraContainer;
					break;
					
				case IMPORTING_MODULE:
					importedObjectType = ModuleInstance;
					break;
					
				case LOADING_ALL:
					break;
					
				case LOADING_NEW_INTERFACES:
				default:
					Assert.assertTrue( false );
					break;
			}
			
			if( _presuppliedID >= 0 && importedObjectType && object is importedObjectType )
			{
				Assert.assertFalse( _model.doesObjectExist( _presuppliedID ) );
				object.id = _presuppliedID;
				_presuppliedID = -1;
				return;
			}
			
			object.id = _model.generateNewID();
		} 
		
		
		private function handleLoadError():void
		{
			Assert.assertNotNull( _error );
			
			IntegraController.singleInstance.dispatchEvent( new LoadFailedEvent( _error ) );
			
			var multiCall:Array = new Array;
			
			for each( var loadedObjectPath:Array in _topLevelLoadedObjectPaths )
			{
				var deleteCall:Object = new Object;
				deleteCall.methodName = "command.delete";
				deleteCall.params = [ loadedObjectPath ];
				multiCall.push( deleteCall );
			}

			var deleteObjectsCall:IntegraConnection = new IntegraConnection( _serverUrl );
			deleteObjectsCall.addArrayParam( multiCall );
			deleteObjectsCall.addEventListener( Event.COMPLETE, onFailedLoadDeleted );
			deleteObjectsCall.callQueued( "system.multicall" );
		}
		
		
		private function onFailedLoadDeleted( event:Event ):void
		{
			var response:Object = event.target.getResponse();
			
			IntegraController.singleInstance.loadModel();			
		}

		
		public static const LOADING_ALL:String = "loadingAll";
		public static const IMPORTING_TRACK:String = "importingTrack";
		public static const IMPORTING_BLOCK:String = "importingBlock";
		public static const IMPORTING_MODULE:String = "importingModule";
		public static const LOADING_NEW_INTERFACES:String = "loadingNewInterfaces";
		
		
		private var _model:IntegraModel = null;
		private var _completionDispatcher:EventDispatcher = null;
		
		private var _interfaceListCall:IntegraConnection = null;

		private var _loadPhase:String = null;
		
		private var _serverUrl:String = null;

		private var _branchPath:Array = null;
		private var _presuppliedID:int = -1;
		private var _mode:String = LOADING_ALL;
		private var _topLevelLoadedObjectPaths:Vector.<Array> = null;
		private var _loadHierarchyLevel:int = -1;
		
		private var _shouldAddDefaultNewProjectObjects:Boolean = false;
		private var _error:String = null;
		
		private var _timeoutTimer:Timer = new Timer( _timeoutMilliseconds, 1 );
		
		private const _timeoutMilliseconds:int = 5000;
	}
}
