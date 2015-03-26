xquery version "1.0-ml";

import module namespace spawnlib = "http://marklogic.com/spawnlib" at "/spawn/lib/spawnlib.xqy";

declare variable $map := map:map(xdmp:get-request-body('xml')/node());
declare variable $q := map:get($map, 'query');
declare variable $vars := map:get($map, 'vars');
declare variable $options := map:get($map, 'options');

spawnlib:spawn-local-task($q, $vars, $options)