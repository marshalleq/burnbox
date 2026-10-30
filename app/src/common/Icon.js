// Thin wrapper so templates can keep using icon(name="copy") and
// icon(name="regular/file"), as they did with the Vue 2 icon library.
import { h } from 'vue';
import { library } from '@fortawesome/fontawesome-svg-core';
import { FontAwesomeIcon } from '@fortawesome/vue-fontawesome';
import {
  faArrowLeft, faArrowRight, faCheck, faCloudUploadAlt, faCopy, faDownload, faEnvelope,
  faExclamationTriangle, faEye, faKey, faPlus, faPlusCircle, faQrcode, faSignInAlt,
  faSpinner, faSyncAlt, faTimes, faUndoAlt, faUpload
} from '@fortawesome/free-solid-svg-icons';
import {
  faFile, faFileAlt, faFileArchive, faFileAudio, faFileImage, faFilePdf, faFileVideo
} from '@fortawesome/free-regular-svg-icons';

library.add(
  faArrowLeft, faArrowRight, faCheck, faCloudUploadAlt, faCopy, faDownload, faEnvelope,
  faExclamationTriangle, faEye, faKey, faPlus, faPlusCircle, faQrcode, faSignInAlt,
  faSpinner, faSyncAlt, faTimes, faUndoAlt, faUpload,
  faFile, faFileAlt, faFileArchive, faFileAudio, faFileImage, faFilePdf, faFileVideo
);

export default {
  name: 'Icon',
  props: {
    name: { type: String, required: true },
    scale: { type: [Number, String], default: 1 },
    flip: { type: String, default: undefined }
  },
  render() {
    const regular = this.name.startsWith('regular/');
    const name = regular ? this.name.slice('regular/'.length) : this.name;
    return h(FontAwesomeIcon, {
      icon: [regular ? 'far' : 'fas', name],
      // site styles (public/assets/styles.css) target .fa-icon
      class: 'fa-icon',
      flip: this.flip,
      style: Number(this.scale) !== 1 ? { fontSize: this.scale + 'em' } : undefined
    });
  }
};
