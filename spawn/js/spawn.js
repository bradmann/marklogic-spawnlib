$(document).ready(function() {
	var updateTimer = null;
	var refreshRate = 1000;
	var totalInactiveJobs = 0;
	var pageSize = 10;
	var page = 1;
	$('#urisQuery').val('xquery version "1.0-ml";\n(: ENTER YOUR URI QUERY HERE :)');
	$('#xformQuery').val('xquery version "1.0-ml";\ndeclare variable $URI external;\n(: ENTER YOUR TRANSFORM QUERY HERE :)');
	var urisEditor = CodeMirror.fromTextArea($('#urisQuery')[0], {mode: "xquery", lineNumbers: true});
	var xformEditor = CodeMirror.fromTextArea($('#xformQuery')[0], {mode: "xquery", lineNumbers: true});

	$('#main_tabs a[data-toggle="tab"]').on('shown.bs.tab', function(evt, ui) {
		var target = $(evt.target).attr('href');
		if (target == '#tab2') {
			urisEditor.refresh();
			xformEditor.refresh();
		}
	});

	$('#task_create_button').on('click', function(evt, ui) {
		createSpawnJob();
		return false;
	});

	$('#refresh_rate a').click(function(evt, ui) {
		evt.preventDefault();
		refreshRate = parseInt($(this).attr('data-value')) * 1000;
		$('#refresh_rate a').html(function(i, html) {
				return $('<div>' + html + '</div>').text();
			});
		$(this).html('<strong>' + $(this).text() + '</strong>');
		refreshData();
		$.cookie("refresh_rate", refreshRate.toString(), {expires: 999});
	});

	$('#new_spawn_throttle a').click(function(evt, ui) {
		evt.preventDefault();
		var throttle = $(this).text();
		$(this).parents('.dropdown').children('button').attr('value', throttle).contents().first().replaceWith(throttle.toString() + " ");
	});

	$('#language_dropdown a').click(function(evt, ui) {
		evt.preventDefault();
		var language = $(this).text();
		$(this).parents('.dropdown').children('button').attr('value', language.toLowerCase()).contents().first().replaceWith(language.toString() + " ");
		urisEditor.setOption("mode", language.toLowerCase());
		xformEditor.setOption("mode", language.toLowerCase());
	});

		$('#prev_page_button').click(function(evt, ui) {
		evt.preventDefault();
		if (page == 1) {
			return;
		}
		page -= 1;
		refreshData();
	});

	$('#next_page_button').click(function(evt, ui) {
		evt.preventDefault();
		if (page >= Math.ceil(totalInactiveJobs / pageSize)) {
			return;
		}
		page += 1;
		refreshData();
	});

	$('#debug').click(function(evt, ui) {
		evt.preventDefault();
		$.ajax({
			url: 'get-server-fields.xqy'
		})
		.done(function(data) {
			var success = data['success'];
			var msg = data['message'];
			if (!success) {
				showError(null, null, msg);
				return;
			}
			$('#serverFieldDialog table tbody').empty();
			var results = data['results'];
			for (var i=0; i<results.length; i++) {
				var host = results[i]['host-name'];
				var fields = results[i]['fields'];
				for (var j=0; j<fields.length; j++) {
					var html = $('<tr/>').append('<td>' + host + '</td><td>' + fields[j]['key'] + '</td><td>' + fields[j]['value'] + '</td></tr>');
					$('#serverFieldDialog table tbody').append(html);
				}
			}
			
			$('#serverFieldDialog').modal('show');
		})
		.fail(showError);
	});

	$('#clearAllFieldsButton').click(function(evt, ui) {
		evt.preventDefault();
		$.ajax({
			url: 'clear-server-fields.xqy'
		})
		.done(function(data) {
			var success = data['success'];
			var msg = data['message'];
			if (!success) {
				showError(null, null, msg);
				return;
			}
			$('#serverFieldDialog table tbody').empty();
		})
		.fail(showError);
	});

	$('body').on('click', 'button.kill', function(evt, ui) {
		var id = $(this).attr('data-job-id');
		$.ajax({
			url: "kill.xqy",
			type: "POST",
			data: {"job-id": id}
		})
		.done(function(data) {
			refreshData();
		});
	});

	$('table').on('click', '.task_link', function(evt, ui) {
		evt.preventDefault();
		var jobID = $(this).text();
		$.ajax({
			url: "progress.xqy",
			data: {"job-id": jobID, "detail": "full"},
			type: "GET"
		})
		.done(function(data) {
			var success = data['success'];
			var msg = data['message'];
			if (!success) {
				showError(null, null, msg);
				return;
			}
			var job = data['results'][0];
			urisEditor.getDoc().setValue(job['uriquery']);
			xformEditor.getDoc().setValue(job['transformquery']);
			urisEditor.setOption("mode", job['language']);
			xformEditor.setOption("mode", job['language']);
			$('#new_spawn_throttle button').val(job['throttle']).contents().first().replaceWith(job['throttle'] + " ");
			$('#language_dropdown button').val(job['language']).contents().first().replaceWith(job['language'] + " ");
			$('#inforest').prop('checked', job['inforest']);
			$('.nav li').eq(1).find('a[data-toggle="tab"]').click();
		})
		.fail(showError);
	});

	$('table').on('click', '.error_link', function(evt, ui) {
		evt.preventDefault();
		var jobID = $(this).attr('data-id');
		$.ajax({
			url: "progress.xqy",
			data: {"job-id": jobID, "detail": "full"},
			type: "GET"
		})
		.done(function(data) {
			var success = data['success'];
			var msg = data['message'];
			if (!success) {
				showError(null, null, msg);
				return;
			}
			var job = data['results'][0];
			var hostStatuses = job['hoststatus'];
			$('#uriErrorTable tbody').empty();
			$('#transformErrorTable tbody').empty();
			for (var host in hostStatuses) {
				if (hostStatuses[host]['urierror']) {
					$('#uriErrorTable tbody').append('<tr><td>' + host + '</td><td>' + hostStatuses[host]['urierror'] + '</td></tr>');
				}
				for (var idx in hostStatuses[host]['transformerrors']) {
					$('#transformErrorTable tbody').append('<tr><td>' + host + '</td><td>' + hostStatuses[host]['transformerrors'][idx]['uri'] + '</td><td>' + hostStatuses[host]['transformerrors'][idx]['error'] + '</td></tr>');
				}
			}

			$('#jobErrorDialog').modal('show');
		})
		.fail(showError);
	});

	$('body').on('click', 'button.remove', function(evt, ui) {
		var id = $(this).attr('data-job-id');
		$.ajax({
			url: "remove.xqy",
			type: "POST",
			data: {"job-id": id}
		})
		.done(function(data) {
			refreshData();
		});
	});

	$('body').on('click', 'div.throttle-dropdown a', function(evt, ui) {
		evt.preventDefault();
		var id = $(this).parents('.dropdown-menu').attr('data-job-id');
		var throttle = parseInt($(this).text());
		$(this).parents('.dropdown').children('button').contents().first().replaceWith(throttle.toString() + " ");
		$.ajax({
			url: "throttle.xqy",
			type: "POST",
			data: {"job-id": id, "throttle": throttle}
		})
		.done(function(data) {
			refreshData();
		});
	});

	function createSpawnJob() {
		var uriq = urisEditor.getValue();
		var xq = xformEditor.getValue();

		var inforest = $('#inforest').is(':checked');
		var throttle = $('#new_spawn_throttle button').attr('value');
		var language = $('#language_dropdown button').attr('value');

		var data = {
			'uris-query': uriq,
			'xform-query': xq,
			'inforest': inforest,
			'throttle': throttle,
			'language': language
		};

		$.ajax({
			url: "create.xqy",
			type: "POST",
			data: data, 
			dataType: "json",
			cache: false
		})
		.done(function(json) {
			var success = json['success'];
			var msg = json['message'];
			if (!success) {
				showError(null, null, msg);
				return;
			}
			var id = json['id'];
			$('#message').parent().show();
			$('#message').removeClass("alert-warning alert-info alert-danger").addClass("alert-success");
			$('#message_text').html(msg);
			$('#message').fadeIn('fast');
			$('#message').delay(4000).fadeOut('slow', function() {$('#message').parent().hide()});
			clearTimeout(updateTimer);
			updateTimer = setTimeout(refreshData, 1000);
			$('.nav li').eq(0).find('a[data-toggle="tab"]').click();
		})
		.fail(showError);
	};

	function showError(jqXHR, textStatus, errorThrown) {
		$('#message').parent().show();
		$('#message').removeClass("alert-warning alert-info alert-success").addClass("alert-danger");
		$('#message_text').html('<p class="error"><strong>Oops! </strong>' + errorThrown + '</p>');
		$('#message').fadeIn('fast');
		$('#message').delay(4000).fadeOut('slow', function() {$('#message').parent().hide()});
	}

	function refreshData() {
		if (!$('.dropdown').hasClass('open')) {
			clearTimeout(updateTimer);
			var start = ((page - 1) * pageSize) + 1
			var end = page * pageSize
			$.ajax({
				url: "progress.xqy?start=" + start + '&end=' + end,
				type: "GET"
			})
			.done(function(data) {
				var runningJobs = [];
				var otherJobs = [];
				for (var key in data['results']) {
					var job = data['results'][key];
					if (job['status'] == 'running' || job['status'] == 'initializing') {
						runningJobs.push(job);
					} else {
						otherJobs.push(job);
					}
				}
				$('#running_jobs_table tbody').html($('#running_row_tmpl').render(runningJobs));
				$('#job_history_table tbody').html($('#history_row_tmpl').render(otherJobs));
				totalInactiveJobs = parseInt(data['totalInactiveJobs']);
				updatePager(totalInactiveJobs);
			}).always(function() {
				updateTimer = setTimeout(refreshData, refreshRate);
 			});
		} else {
			updateTimer = setTimeout(refreshData, 1000);
		}
	}

	function updatePager(total) {
		var end = page * pageSize;
		if (page == 1) {
			$('#prev_page_button').parent().addClass('disabled');
		} else {
			$('#prev_page_button').parent().removeClass('disabled');
		}

		if (end >= total) {
			$('#next_page_button').parent().addClass('disabled');
		} else {
			$('#next_page_button').parent().removeClass('disabled');
		}

		$('#page_label a').text('page ' + page + ' of ' + Math.floor((total / pageSize) + 1))
	}

	var refresh = $.cookie("refresh_rate");
	if (refresh == undefined) {
		refresh = '1000';
		$.cookie("refresh_rate", refresh, {expires: 999});
	}

	refreshRate = parseInt(refresh);

	var selectedRefresh = refreshRate / 1000;

	var menuItem = $('#refresh_rate a[data-value="' + selectedRefresh + '"]');
	menuItem.html('<strong>' + menuItem.text() + '</strong>');

	refreshData();
});