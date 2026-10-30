import { createApp, h } from 'vue';
import Admin from './Admin.vue';
import Icon from './common/Icon';

function parseDate(str) {
  if(!str) return str;
  return new Date(str);
}

function formatDate(dt) {
  if(dt === null) return "";
  const f = function(d) {
    return d < 10 ? '0' + d : d;
  };
  return dt.getFullYear() + '-' + f(dt.getMonth() + 1) + '-' + f(dt.getDate()) + ' ' + f(dt.getHours()) + ':' + f(dt.getMinutes());
}
function isDate(d) {
  return Object.prototype.toString.call(d) === '[object Date]';
}

// Vue 3 has no filters: expose the formatter as a global template method instead.
function formatDateValue(val, format) {
  if(!isDate(val)) {
    val = parseDate(val);
  }
  return isDate(val) ? formatDate(val, format) : val;
}

const app = createApp({
  data() {
    return {
      baseURI: document.head.getElementsByTagName('base')[0].href
    };
  },
  render: () => h(Admin)
});

app.component('icon', Icon);
app.config.globalProperties.$date = formatDateValue;
app.mount('#admin');

window.BURNBOX_VERSION = BURNBOX_VERSION;
