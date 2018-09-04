var assert = require('assert');
var babel = require('babel-core');
var clear = require('clear');
var diff = require('diff');
var fs = require('fs');
var jsonfile = require('jsonfile');
var path = require('path');
var Mocha = require('mocha');

require('babel-register');

var pluginPath = require.resolve('../src');

function runTests() {
	var testsPath = __dirname + '/fixtures/';

	fs.readdirSync(testsPath).map(function(item) {
		return {
			path: path.join(testsPath, item),
			name: item,
		};
	}).filter(function(item) {
		return fs.statSync(item.path).isDirectory();
	}).forEach(runTest);

	runMocha();
}

function runMocha() {
	// Instantiate a Mocha instance.
	var mocha = new Mocha();

	var testDir = path.join(__dirname, 'mocha')

	var suite = path.join(testDir, 'suite.js')

	var output = babel.transformFileSync(suite, {
		plugins: [pluginPath]
	});

	var suiteCompiled = path.join(testDir, '.suite_compiled.js');

	fs.writeFileSync(suiteCompiled, output.code);

	delete require.cache[require.resolve(suiteCompiled)];

	mocha.addFile(suiteCompiled);

	// Run the tests.
	mocha.run();
}

function runTest(dir) {
	var babelOptions = {
		plugins: [pluginPath]
	}

	babelRcPath = path.join(dir.path, '.babelrc');
	try {
		fs.accessSync(babelRcPath);
		babelOptions = jsonfile.readFileSync(babelRcPath);
	} catch(e) {}

	var output = babel.transformFileSync(dir.path + '/actual.js', babelOptions);

	var expected = fs.readFileSync(dir.path + '/expected.js', 'utf-8');

	function normalizeLines(str) {
		return str.trimRight().replace(/\r\n/g, '\n');
	}

	process.stdout.write(dir.name);
	process.stdout.write('\n\n');

	diff.diffLines(normalizeLines(output.code), normalizeLines(expected))
	.forEach(function (part) {
		var value = part.value;
		if (part.added) {
			value = part.value;
		} else if (part.removed) {
			value = part.value;
		}


		process.stdout.write(value);
	});

	process.stdout.write('\n\n\n');
}

if (process.argv.indexOf('--watch') >= 0) {
	require('watch').watchTree(__dirname + '/..', {
		ignoreDotFiles: true
	}, function () {
		delete require.cache[pluginPath];
		clear();
		console.log('Press Ctrl+C to stop watching...');
		console.log('================================');
		try {
			runTests();
		} catch (e) {
			console.error(e.stack);
		}
	});
} else {
	runTests();
}
