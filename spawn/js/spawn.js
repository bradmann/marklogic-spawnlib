$(document).ready(function() {
	var updateTimer = null;
	var refreshRate = 1000;
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
		clearInterval(updateTimer);
		refreshData();
		$.cookie("refresh_rate", refreshRate.toString(), {expires: 999});
	});

	$('body').on('click', 'button.kill', function(evt, ui) {
		var id = $(this).attr('data-job-id');
		$.ajax({
			url: "kill.xqy",
			type: "POST",
			data: {"job-id": id}
		})
		.done(function(data) {
			clearInterval(updateTimer);
			refreshData();
		});
	});

	$('table').on('click', '.task_link', function(evt, ui) {
		evt.preventDefault();
		var uri_query = $(this).parents('tr').find('input.uri_query').val();
		var xform_query = $(this).parents('tr').find('input.transform_query').val();
		urisEditor.getDoc().setValue(uri_query);
		xformEditor.getDoc().setValue(xform_query);
		$('.nav li').eq(1).find('a[data-toggle="tab"]').click();
	});

	$('body').on('click', 'button.remove', function(evt, ui) {
		var id = $(this).attr('data-job-id');
		$.ajax({
			url: "remove.xqy",
			type: "POST",
			data: {"job-id": id}
		})
		.done(function(data) {
			clearInterval(updateTimer);
			refreshData();
			updateTimer = setInterval(refreshData, 1000);
		});
	});

	function createSpawnJob() {
		var uriq = urisEditor.getValue();
		var xq = xformEditor.getValue();

		var inforest = $('#inforest').is(':checked');

		var data = {
			'uris-query': uriq,
			'xform-query': xq,
			'inforest': inforest
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
				createFailed(null, null, msg);
				return;
			}
			var id = json['id'];
			$('#message').removeClass("alert-warning alert-info alert-danger").addClass("alert-success");
			$('#message_text').html(msg);
			$('#message').fadeIn('fast');
			$('#message').delay(4000).fadeOut('slow');
			clearInterval(updateTimer);
			updateTimer = setTimeout(refreshData, 1000);
			$('.nav li').eq(0).find('a[data-toggle="tab"]').click();
		})
		.fail(createFailed);
	};

	function createFailed(jqXHR, textStatus, errorThrown) {
		$('#message').removeClass("alert-warning alert-info alert-success").addClass("alert-danger");
		$('#message_text').html('<p class="error"><strong>Oops! </strong>' + errorThrown + '</p>');
		$('#message').fadeIn('fast');
		$('#message').delay(4000).fadeOut('slow');
	}

	function refreshData() {
		$.ajax({
			url: "progress.xqy",
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
		})
		.always(function() {
			updateTimer = setTimeout(refreshData, refreshRate);
		});
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