(:
Copyright 2015 MarkLogic Corporation

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
:)
xquery version "1.0-ml";

import module namespace spawnlib = "http://marklogic.com/spawnlib" at "/spawn/lib/spawnlib.xqy";

declare option xdmp:mapping "false";

xdmp:set-response-content-type("text/html"),
'<!DOCTYPE html>',
<html xmlns="http://www.w3.org/1999/xhtml">
	<head>
		<meta charset="utf-8"/>
		<meta http-equiv="X-UA-Compatible" content="IE=edge"/>
		<meta name="viewport" content="width=device-width, initial-scale=1"/>
		<title>spawnlib</title>

		<!-- Bootstrap -->
		<link href="css/bootstrap.min.css" rel="stylesheet"/>
		<link href="css/font-awesome.min.css" rel="stylesheet"/>
		<link href="css/codemirror.css" rel="stylesheet"/>
		<link href="css/spawnlib.css" rel="stylesheet"/>
		<link rel="icon" type="image/png" href="images/favicon.ico"/>

		<!-- HTML5 Shim and Respond.js IE8 support of HTML5 elements and media queries -->
		<!-- WARNING: Respond.js doesn't work if you view the page via file:// -->
		<!--[if lt IE 9]>
			<script src="../public/js/lib/html5shiv.js"></script>
			<script src="../public/js/lib/respond.min.js"></script>
		<![endif]-->
	</head>
	<body>
		<nav class="navbar navbar-inverse navbar-static-top" role="navigation">
			<div class="container-fluid">
				<!-- Brand and toggle get grouped for better mobile display -->
				<div class="navbar-header">
					<button type="button" class="navbar-toggle" data-toggle="collapse" data-target="#main_tabs">
						<span class="sr-only">Toggle navigation</span>
						<span class="icon-bar"></span>
						<span class="icon-bar"></span>
						<span class="icon-bar"></span>
					</button>
					<a class="navbar-brand" href="#"><img src="images/spawnlib-icon-clear.png" style="width: 30px; height: 30px; margin-top: -5px;"/> spawnlib</a>
				</div>

				<!-- Collect the nav links, forms, and other content for toggling -->
				<div class="collapse navbar-collapse" id="main_tabs">
					<ul class="nav navbar-nav">
						<li class="active"><a href="#tab1" data-toggle="tab">Status</a></li>
						<li><a href="#tab2" data-toggle="tab">Create</a></li>
					</ul>
					<ul class="nav navbar-nav pull-right">
						<li role="presentation" class="dropdown">
							<a class="dropdown-toggle" data-toggle="dropdown" href="#" role="button" aria-expanded="false">Refresh <span class="caret"></span></a>
							<ul id="refresh_rate" class="dropdown-menu pull-right" role="menu">
								<li><a href="#" data-value="1">1 second</a></li>
								<li><a href="#" data-value="5">5 seconds</a></li>
								<li><a href="#" data-value="10">10 seconds</a></li>
								<li><a href="#" data-value="30">30 seconds</a></li>
								<li><a href="#" data-value="60">60 seconds</a></li>
							</ul>
						</li>
					</ul>
						<ul class="nav navbar-nav pull-right">
							<li><a href="#debug" id="debug"><span class="glyphicon glyphicon-wrench"></span></a></li>
						</ul>
				</div><!-- /.navbar-collapse -->
			</div><!-- /.container-fluid -->
		</nav>
		<div class="tab-content">
			<div id="tab1" class="tab-pane active fade in container col-md-10 col-md-offset-1">
				<div class="panel panel-default">
					<div class="panel-heading"><h3 class="panel-title">Active Jobs</h3></div>
					<table class="table table-striped" id="running_jobs_table">
						<thead><tr><th>id</th><th>name</th><th>language</th><th>status</th><th>inforest</th><th>created</th><th>progress</th><th>total tasks</th><th>throttle</th><th></th></tr></thead>
						<tbody>
						</tbody>
					</table>
				</div>
				<div class="panel panel-default">
					<div class="panel-heading">
						<h3 class="panel-title">Inactive Jobs
							<ul class="pagination pagination-sm pull-right" style="margin: -5px 0">
								<li>
									<a href="#" aria-label="Previous" id="prev_page_button">
										<span aria-hidden="true">&laquo;</span>
									</a>
								</li>
								<li id="page_label" class="disabled"><a href="#">page 1 of 1</a></li>
								<li>
									<a href="#" aria-label="Next" id="next_page_button">
										<span aria-hidden="true">&raquo;</span>
									</a>
								</li>
							</ul>
						</h3>
					</div>
					<table class="table table-striped" id="job_history_table">
						<thead><tr><th>id</th><th>name</th><th>language</th><th>status</th><th>inforest</th><th>created</th><th>completed</th><th>progress</th><th>total tasks</th><th><button type="button" id="removeall_button" class="btn btn-xs btn-default"><span class="glyphicon glyphicon-remove" aria-hidden="true"></span> remove all</button></th></tr></thead>
						<tbody>
						</tbody>
					</table>
				</div>
			</div>
			<div id="tab2" class="tab-pane fade container col-md-10 col-md-offset-1">
				<div class="panel panel-default">
					<div class="panel-heading">
						<div class="pull-right">
							<div id="language_dropdown" class="dropdown">
								<button class="btn btn-xs language-toggle" type="button" id="languageDropdown" data-toggle="dropdown" aria-haspopup="true" aria-expanded="true" value="xquery">
									xquery
									<span class="caret"></span>
								</button>
								<ul class="dropdown-menu" aria-labelledby="languageDropdown">
									<li><a href="#">xquery</a></li>
									{
										if (xs:int(fn:substring(xdmp:version(), 1, 1)) ge 8) then
											<li><a href="#">javascript</a></li>
										else ()
									}
								</ul>
							</div>
						</div>
						<h3 class="panel-title">Run CoRB Job</h3>
					</div>
					<div class="panel-body">
						<form id="spawnlib_create_form" role="form">
							<div class="form-group">
									<label for="urisQuery">URIs Query:</label>
								<textarea id="urisQuery" rows="5" required="required"></textarea>
							</div>
							<div class="form-group">
									<label for="xformQuery">Transform Query: </label>
								<textarea id="xformQuery" rows="5" required="required"></textarea>
							</div>
							Throttle
							<div id="new_spawn_throttle" class="dropdown">
								<button class="btn btn-default dropdown-toggle" type="button" id="throttleDropdown" data-toggle="dropdown" aria-haspopup="true" aria-expanded="true" value="10">
									10
									<span class="caret"></span>
								</button>
									<ul class="dropdown-menu" aria-labelledby="throttleDropdown">
									<li><a href="#">1</a></li>
									<li><a href="#">2</a></li>
									<li><a href="#">3</a></li>
									<li><a href="#">4</a></li>
									<li><a href="#">5</a></li>
									<li><a href="#">6</a></li>
									<li><a href="#">7</a></li>
									<li><a href="#">8</a></li>
									<li><a href="#">9</a></li>
									<li><a href="#">10</a></li>
								</ul>
							</div>
							<div class="checkbox">
								<label><input type="checkbox" name="type" id="inforest" value="true" checked="true"/> In-forest Evaluation</label>
							</div>
							<div id="task_create_toolbar" class="btn-toolbar" role="toolbar">
								<div class="btn-group">
									<button id="task_create_button" class="btn btn-primary">Run CoRB Job</button>
								</div>
							</div>
						</form>

					</div>
				</div>
			</div>
		</div>

		<div class="navbar navbar-fixed-bottom" style="display: none">
			<div id="message" class="alert alert-info" style="display: none">
				<span id="message_text">This is an system message.</span>
				<button type="button" class="close" data-dismiss="alert" aria-hidden="true">×</button>
			</div>
		</div>

			<div class="modal fade" id="jobErrorDialog" role="dialog" aria-labelledby="myModalLabel" aria-hidden="true" data-backdrop="static">
				<div class="modal-dialog" style="width: 1000px">
					<div class="modal-content">
						<div class="modal-body">
							<h5>URI Errors</h5>
							<table class="table table-striped" id="uriErrorTable">
								<thead><tr><th>Host</th><th>Error</th></tr></thead>
								<tbody>
								</tbody>
							</table>
							<h5>Transform Errors</h5>
							<table class="table table-striped" id="transformErrorTable">
								<thead><tr><th>Host</th><th>URI</th><th>Error</th></tr></thead>
								<tbody>
								</tbody>
							</table>
						</div>
						<div class="modal-footer">
							<button type="button" class="btn btn-primary" data-dismiss="modal">Close</button>
						</div>
					</div>
				</div>
			</div>

			<div class="modal fade" id="serverFieldDialog" role="dialog" aria-labelledby="myModalLabel" aria-hidden="true" data-backdrop="static">
				<div class="modal-dialog" style="width: 1000px">
					<div class="modal-content">
						<div class="modal-body">
							<h5>Server Fields <span class="pull-right"><button class="btn btn-default btn-xs" id="clearAllFieldsButton"><span class="glyphicon glyphicon-remove" aria-hidden="true"></span> clear fields</button></span></h5>
							<table class="table table-striped" id="uriErrorTable">
								<thead><tr><th>Host</th><th>Field</th><th>Data</th></tr></thead>
								<tbody>
								</tbody>
							</table>
						</div>
						<div class="modal-footer">
							<button type="button" class="btn btn-primary" data-dismiss="modal">Close</button>
						</div>
					</div>
				</div>
			</div>

		<script id="running_row_tmpl" type="text/x-jquery-tmpl">
			<tr>
				<td><a href="#" class="task_link">{{{{:id}}}}</a></td>
				<td>{{{{:name}}}}</td>
				<td>{{{{:language}}}}</td>
				<td>{{{{:status}}}}</td>
				<td>{{{{:inforest}}}}</td>
				<td>{{{{:created}}}}</td>
				<td>{{{{:progress}}}}</td>
				<td>{{{{:total}}}}</td>
				<td>
					<div class="dropdown throttle-dropdown">
							<button class="btn btn-default btn-xs dropdown-toggle" type="button" id="throttleDropdown-{{{{:id}}}}" data-toggle="dropdown" aria-haspopup="true" aria-expanded="true">
							{{{{:throttle}}}}
							<span class="caret"></span>
						</button>
							<ul class="dropdown-menu" aria-labelledby="throttleDropdown-{{{{:id}}}}" data-job-id="{{{{:id}}}}">
							<li><a href="#">1</a></li>
							<li><a href="#">2</a></li>
							<li><a href="#">3</a></li>
							<li><a href="#">4</a></li>
							<li><a href="#">5</a></li>
							<li><a href="#">6</a></li>
							<li><a href="#">7</a></li>
							<li><a href="#">8</a></li>
							<li><a href="#">9</a></li>
							<li><a href="#">10</a></li>
						</ul>
					</div>
				</td>
				<td><button class="btn btn-danger btn-xs kill" data-job-id="{{{{:id}}}}">kill</button></td>
			</tr>
		</script>
		<script id="history_row_tmpl" type="text/x-jquery-tmpl">
			<tr>
				<td><a href="#" class="task_link">{{{{:id}}}}</a></td>
				<td>{{{{:name}}}}</td>
				<td>{{{{:language}}}}</td>
				{{{{if status != "error"}}}}
					<td>{{{{:status}}}}</td>
				{{{{else}}}}
						<td><a href="#" class="error_link" data-id="{{{{:id}}}}">{{{{:status}}}}</a></td>
				{{{{/if}}}}
				<td>{{{{:inforest}}}}</td>
				<td>{{{{:created}}}}</td>
				<td>{{{{:completed}}}}</td>
				<td>{{{{:progress}}}}</td>
				<td>{{{{:total}}}}</td>
					<td><button class="btn btn-default btn-xs remove" data-job-id="{{{{:id}}}}"><span class="glyphicon glyphicon-remove" aria-hidden="true"></span> remove</button></td>
			</tr>
		</script>

		<script src="js/lib/jquery-1.7.1.min.js" type="text/javascript"></script>
		<script src="js/lib/jquery.cookie.js" type="text/javascript"></script>
		<script src="js/lib/less-1.3.0.min.js" type="text/javascript"></script>
		<script src="js/lib/jsrender.js" type="text/javascript"></script>
		<script src="js/lib/codemirror.js" type="text/javascript"></script>
		<script src="js/lib/xquery.js" type="text/javascript"></script>
		<script src="js/lib/javascript.js" type="text/javascript"></script>
		<script src="js/bootstrap.min.js" type="text/javascript"></script>
		<script src="js/spawn.js" type="text/javascript"></script>
	</body>
</html>