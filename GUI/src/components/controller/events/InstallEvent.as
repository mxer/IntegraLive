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


package components.controller.events
{
	import flash.events.Event;

	public class InstallEvent extends Event
	{
		public function InstallEvent( mode:String = InstallEvent.STARTED, description:String = "" )
		{
			super( EVENT_NAME );
			
			_mode = mode;
			_description = description;
		}
		
		public function get mode():String { return _mode; } 
		public function get description():String { return _description; } 

		public static const EVENT_NAME:String = "install";
		
		public static const STARTED:String = "started";
		public static const FINISHED:String = "finished";

		private var _mode:String = ImportEvent.STARTED; 
		private var _description:String;
		
	}
}