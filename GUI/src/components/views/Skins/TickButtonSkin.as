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
 
 
 
package components.views.Skins
{
	import flash.filters.GlowFilter;
	
	import mx.skins.halo.ButtonSkin;
	
	import components.model.userData.ColorScheme;
	
	public class TickButtonSkin extends ButtonSkin
	{
		public function TickButtonSkin()
		{
			super();
		}
		
		override protected function updateDisplayList( unscaledWidth:Number, unscaledHeight:Number ):void
		{
			graphics.clear();
			
			var nameLower:String = name.toLowerCase();
			
			var over:Boolean = ( nameLower.indexOf( "over" ) >= 0 );
			var selected:Boolean = ( nameLower.indexOf( "selected" ) >= 0 );
			var down:Boolean = ( nameLower.indexOf( "down" ) >= 0 );
			var disabled:Boolean = ( nameLower.indexOf( "disabled" ) >= 0 );

			var borderColor:uint;
			var selectedColor:uint;
			
			switch( getStyle( ColorScheme.STYLENAME ) )
			{
				default:
				case ColorScheme.LIGHT:
					borderColor = 0x747474;
					selectedColor = 0x313131;
					break;

				case ColorScheme.DARK:
					borderColor = 0x8c8c8c;
					selectedColor = 0xcfcfcf;
				break;
			}
			
			var color:uint = getStyle( "color" );
			if( color == 0 ) color = borderColor;
			
			var diameter:Number = Math.min( width, height );
			var radius:Number = diameter / 2;
			
			graphics.lineStyle( 1, ( over || down ) ? selectedColor : borderColor, disabled ? 0.5 : 1 );
			
			graphics.beginFill( disabled ? borderColor : color, 0.2 );
			graphics.drawCircle( radius, radius, radius );
			graphics.endFill();
			
			//draw the tick
			if( selected )
			{
				graphics.lineStyle( 2, selectedColor );
				graphics.moveTo( radius * 0.5, radius );
				graphics.lineTo( radius, radius * 1.5 );
				graphics.lineTo( radius * 1.5, radius * 0.5 );
			}
			
			//update the glow
			var filterArray:Array = new Array;
			if( down )
			{
				filterArray.push( new GlowFilter( color, 0.6, 10, 10, 3 ) );
			}	
			filters = filterArray;
		}
	}
}