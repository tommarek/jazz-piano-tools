import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
	appId: 'online.markovi.voicings',
	appName: 'Comp',
	// The SvelteKit static build is the entire app payload.
	webDir: 'build',
	backgroundColor: '#13110f',
	ios: {
		contentInset: 'never',
		backgroundColor: '#13110f'
	},
	android: {
		backgroundColor: '#13110f'
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
