/* libIntegra modular audio framework
 *
 * Copyright (C) 2007 Birmingham City University
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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, 
 * USA.
 */


#ifndef INTEGRA_DSP_ENGINE_H
#define INTEGRA_DSP_ENGINE_H

#include "api/common_typedefs.h"
#include "api/error.h"
#include "node.h"
#include "midi_engine.h"
#include "threaded_queue.h"

#include <pthread.h>


extern "C"	//setup functions for externals
{
	void bonk_tilde_setup();
	void expr_setup();		
	void fiddle_tilde_setup();
	void lrshift_tilde_setup();
	void partconv_tilde_setup();
	void freeverb_tilde_setup();
	void soundfile_info_setup();
	void fsplay_tilde_setup();
        void copy_setup();
}


namespace pd
{
	class PdBase;
	class List;
	struct Message;
}

namespace integra_api
{
	class ISetCommand;
}


namespace integra_internal
{
	class CServer;
	class IMidiEngine;
	class CMidiInputFilterer;

	class CDspEngine : public IThreadedQueueOutputSink<pd::Message>
	{
		public:

			CDspEngine( CServer &server );
			~CDspEngine();

			CError add_module( internal_id id, const string &patch_path );
			CError remove_module( internal_id id );
			CError connect_modules( const CNodeEndpoint &source, const CNodeEndpoint &target );
			CError disconnect_modules( const CNodeEndpoint &source, const CNodeEndpoint &target );
			CError send_value( const CNodeEndpoint &target );

			void process_buffer( const float *input, float *output, int input_channels, int output_channels, int sample_rate );

			void dump_patch_to_file( const string &path );
			void ping_all_modules();

			static const int samples_per_buffer;

		private:

			typedef std::list<pd::Message> pd_message_list;

			void setup_libpd();

			string get_patch_file_path() const;


			bool has_configuration_changed( int input_channels, int output_channels, int sample_rate ) const;

			bool is_configuration_valid() const;
			void initialize_audio_configuration( int input_channels, int output_channels, int sample_rate );

			void poll_for_messages();

			void create_host_patch();
			void delete_host_patch();

			void register_externals();

			CError connect_or_disconnect( const CNodeEndpoint &source, const CNodeEndpoint &target, const string &command );

			int get_patch_id( internal_id id ) const;
			int get_stream_connection_index( const CNodeEndpoint &node_endpoint ) const;

			void handle_midi_input();

			bool should_queue_message( const pd::Message &message ) const;

			bool handle_immediate_message( const pd::Message &message );

			bool handle_midi_output( const pd::Message &message );

			void handle_queue_items( const pd_message_list &messages );

			ISetCommand *build_set_command( const pd::List &feedback_arguments ) const;
			void merge_set_command( ISetCommand *command );

			int ping_modules( const node_map &nodes );
			void send_ping( const CNode &node );
			bool is_ping_result( const pd::Message &message ) const;

			void trace_to_pd_log( const string &message ) const;

			void test_map_sanity();

			pd::PdBase *m_pd;

			CServer &m_server;

			bool m_initialised;
			int m_input_channels;
			int m_output_channels;
			int m_sample_rate;

			pthread_mutex_t m_mutex;

			int m_next_module_y_slot;

			int_map m_map_id_to_patch_id;

			CThreadedQueue<pd::Message> *m_feedback_queue;

			typedef std::list<ISetCommand *> set_command_list;
			set_command_list m_set_commands;

			CMidiInputFilterer *m_midi_input_filterer;

			midi_input_buffer_array m_midi_input;

			int m_unanswered_pings;

			static const int max_audio_channels;
			static const string patch_file_name;
			static const string host_patch_name;
			static const string patch_message_target;

			static const string feedback_source;
			static const string broadcast_symbol;
			static const string bang;


			static const int module_x_margin;
			static const int module_y_spacing;

			static const string init_message;
			static const string fini_message;
			static const string ping_message;

			static const string trace_start_tag;
			static const string trace_end_tag;
	};
}



#endif /* INTEGRA_DSP_ENGINE_H */
