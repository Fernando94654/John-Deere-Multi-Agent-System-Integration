import config from '../John-Deere-MultiAgents-Website/vite.config.js';

// Resolve relative to the website root, exposing the versioned Unity build.
export default { ...config, publicDir: '../unity-build' };
