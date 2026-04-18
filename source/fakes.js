var document = { };
var navigator = { };
var Intl = {
    NumberFormat: {
        supportedLocalesOf: function(locales) {
            return locales;
        }
    },
    DateTimeFormat: {
        resolvedOptions: function() {
            return {
                timeZone: 'Africa/Casablanca'
            }
        }
    }
};
const WINDOW = {
    location: {
        hostname: 'www.youtube.com',
        href: 'https://www.youtube.com/'
    }
};
function XMLHttpRequest() { }
