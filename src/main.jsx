import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import './mobile-fit.css'
import './account-actions.css'
import './onboarding-fix.css'
import App from './App.jsx'
createRoot(document.getElementById('root')).render(
  <StrictMode><App /></StrictMode>,
)
