import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
	appId: 'online.markovi.voicings',
	appName: 'Voicings',
	// The SvelteKit static build is the entire app payload.
	webDir: 'build',
	backgroundColor: '#0f1117',
	ios: {
		contentInset: 'never',
		backgroundColor: '#0f1117'
	},
	android: {
		backgroundColor: '#0f1117'
	},
	plugins: {
		CapacitorSQLite: {
			iosDatabaseLocation: 'Library/CapacitorDatabase',
			iosIsEncryption: false,
			androidIsEncryption: false
		}
	}
};

export default config;
