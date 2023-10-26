/*-
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Copyright (c) 2022-2023 Procursus Team <team@procurs.us>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice, this
 *    list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
#include <Availability.h>

#include <sys/fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/syslimits.h>
#include <sys/types.h>

#include <errno.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sysdir.h>
#include <unistd.h>

#include <mach/mach.h>

#include <xpc/xpc.h>

#include "launchctl.h"

#define OS_ALLOC_ONCE_KEY_LIBXPC 1

struct xpc_global_data {
    uint64_t a;
    uint64_t xpc_flags;
    mach_port_t task_bootstrap_port; /* 0x10 */
#ifndef _64
    uint32_t padding;
#endif
    xpc_object_t xpc_bootstrap_pipe; /* 0x18 */
};

#define OS_ALLOC_ONCE_KEY_MAX 100

struct _os_alloc_once_s {
    long once;
    void *ptr;
};

extern struct _os_alloc_once_s _os_alloc_once_table[];


int
launchctl_send_xpc_to_launchd(uint64_t routine, xpc_object_t msg, xpc_object_t *reply)
{
	xpc_object_t bootstrap_pipe = ((struct xpc_global_data *)_os_alloc_once_table[OS_ALLOC_ONCE_KEY_LIBXPC].ptr)->xpc_bootstrap_pipe;

	// Routines that act on a specific service are in the subsystem 2
	// but that require a domain are in the subsystem 3 these are also
	// divided into the routine numbers 0x2XX and 0x3XX, so a quick and
	// dirty bit shift will let us get the correct subsystem.
	xpc_dictionary_set_uint64(msg, "subsystem", routine >> 8);
	xpc_dictionary_set_uint64(msg, "routine", routine);
	int ret = 0;

	//if (__builtin_available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)) {
	//	ret = _xpc_pipe_interface_routine(bootstrap_pipe, 0, msg, reply, 0);
	//} else {
		ret = xpc_pipe_routine(bootstrap_pipe, msg, reply);
	//}
	if (ret == 0 && (ret = xpc_dictionary_get_int64(*reply, "error")) == 0)
		return 0;

	return ret;
}

void
launchctl_setup_xpc_dict(xpc_object_t dict)
{
	if (__builtin_available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)) {
		xpc_dictionary_set_uint64(dict, "type", 7);
	} else {
		xpc_dictionary_set_uint64(dict, "type", 1);
	}
	xpc_dictionary_set_uint64(dict, "handle", 0);
	return;
}

xpc_object_t
launchctl_parse_load_unload(unsigned int domain, int count, char **list)
{
	xpc_object_t ret;
	ret = xpc_array_create(NULL, 0);
	char pathbuf[PATH_MAX*2];
	memset(pathbuf, 0, PATH_MAX*2);

	if (domain != 0) {
		sysdir_search_path_enumeration_state state;
		state = sysdir_start_search_path_enumeration(SYSDIR_DIRECTORY_LIBRARY, SYSDIR_DOMAIN_MASK_LOCAL | SYSDIR_DOMAIN_MASK_SYSTEM);
		while ((state = sysdir_get_next_search_path_enumeration(state, pathbuf)) != 0) {
			strcat(pathbuf, "/LaunchDaemons");
			xpc_array_set_string(ret, XPC_ARRAY_APPEND, pathbuf);
		}
	}

	for (int i = 0; i < count; i++) {
		char *finalpath;
		if (list[i][0] == '/')
			finalpath = strdup(list[i]);
		else {
			getcwd(pathbuf, sizeof(pathbuf));
			asprintf(&finalpath, "%s/%s", pathbuf, list[i]);
		}
		xpc_array_set_string(ret, XPC_ARRAY_APPEND, finalpath);
		free(finalpath);
	}

	return ret;
}



